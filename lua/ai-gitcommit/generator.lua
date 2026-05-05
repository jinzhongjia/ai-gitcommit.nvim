local buffer = require("ai-gitcommit.buffer")
local buffer_state = require("ai-gitcommit.buffer_state")
local config = require("ai-gitcommit.config")
local context = require("ai-gitcommit.context")
local git = require("ai-gitcommit.git")
local prompt = require("ai-gitcommit.prompt")
local providers = require("ai-gitcommit.providers")
local typewriter = require("ai-gitcommit.typewriter")

local M = {}

---@param existing_context? string
---@param amend_note? string
---@return string?
local function merge_extra_context(existing_context, amend_note)
	if not amend_note or amend_note == "" then
		return existing_context
	end

	if not existing_context or existing_context == "" then
		return amend_note
	end

	return string.format("%s\n%s", existing_context, amend_note)
end

---@param bufnr integer
---@param callback fun(diff: string, files: AIGitCommit.StagedFile[], amend_note: string?, err: string?)
local function get_diff_context(bufnr, callback)
	local staged_diff
	local staged_files
	local staged_diff_err
	local staged_files_err
	local pending = 2

	---@param done fun(diff: string, files: AIGitCommit.StagedFile[], amend_note: string?, err: string?)
	local function fetch_head_context(done)
		local head_diff
		local head_files
		local head_diff_err
		local head_files_err
		local head_pending = 2

		local function finish_head()
			if head_pending > 0 then
				return
			end

			if head_diff_err then
				done("", {}, nil, head_diff_err)
				return
			end

			if head_files_err then
				done("", {}, nil, head_files_err)
				return
			end

			done(
				head_diff,
				head_files,
				(
					"This commit message is being amended without staged changes. "
					.. "Use the current HEAD commit diff below as the context to rewrite the message."
				),
				nil
			)
		end

		git.get_head_diff(bufnr, function(diff, err)
			head_diff = diff
			head_diff_err = err
			head_pending = head_pending - 1
			finish_head()
		end)

		git.get_head_files(bufnr, function(files, err)
			head_files = files
			head_files_err = err
			head_pending = head_pending - 1
			finish_head()
		end)
	end

	local function finish_staged()
		if pending > 0 then
			return
		end

		if staged_diff_err then
			callback("", {}, nil, staged_diff_err)
			return
		end

		if staged_files_err then
			callback("", {}, nil, staged_files_err)
			return
		end

		if staged_diff ~= "" then
			callback(staged_diff, staged_files, nil, nil)
			return
		end

		if buffer.get_existing_message(bufnr) == "" or not buffer.is_amend_message_buffer(bufnr) then
			callback(staged_diff, staged_files, nil, nil)
			return
		end

		fetch_head_context(callback)
	end

	git.get_staged_diff(bufnr, function(diff, err)
		staged_diff = diff
		staged_diff_err = err
		pending = pending - 1
		finish_staged()
	end)

	git.get_staged_files(bufnr, function(files, err)
		staged_files = files
		staged_files_err = err
		pending = pending - 1
		finish_staged()
	end)
end

---@param language string
---@param extra_context? string
---@param bufnr? integer
---@param silent? boolean
function M.run(language, extra_context, bufnr, silent)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local state = buffer_state.get(bufnr)
	if state.generating then
		return
	end

	buffer_state.stop_timer(bufnr)
	buffer_state.cancel_stream(bufnr)

	local provider_info, provider_err = config.get_provider()
	if not provider_info then
		if not silent then
			vim.notify(provider_err, vim.log.levels.ERROR)
		end
		return
	end

	state.generating = true
	local expected_changedtick = vim.api.nvim_buf_get_changedtick(bufnr)

	---@param msg string
	---@param level? integer
	local function fail(msg, level)
		buffer_state.cancel_stream(bufnr)
		state.generating = false
		if not silent then
			vim.notify(msg, level or vim.log.levels.ERROR)
		end
	end

	---@return boolean
	local function should_abort_for_buffer_changes()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return true
		end

		return vim.api.nvim_buf_get_changedtick(bufnr) ~= expected_changedtick
	end

	---@param message string
	local function abort_due_to_buffer_changes(message)
		buffer_state.cancel_stream(bufnr)
		state.generating = false
		return fail(message, vim.log.levels.WARN)
	end

	if not silent then
		vim.notify("Generating commit message...", vim.log.levels.INFO)
	end

	get_diff_context(bufnr, function(diff, files, amend_note, diff_err)
		if diff_err then
			return fail("Error: " .. diff_err)
		end

		if diff == "" then
			return fail("No staged changes found", vim.log.levels.WARN)
		end

		local cfg = config.get()
		local processed_diff = context.build_context(diff, cfg)
		local filtered_files = context.filter_files(files, cfg)

		local final_prompt = prompt.build({
			template = cfg.prompt_template,
			language = language,
			extra_context = merge_extra_context(extra_context, amend_note),
			files = filtered_files,
			diff = processed_diff,
		})

		local provider = providers.get(provider_info.name)

		provider.resolve_credentials(provider_info.config, function(creds, creds_err)
			if creds_err then
				return fail(creds_err)
			end

			local provider_config = vim.deepcopy(provider_info.config)
			if creds.api_key ~= nil then
				provider_config.api_key = creds.api_key
			end
			if creds.endpoint then
				provider_config.endpoint = creds.endpoint
			end
			if creds.model then
				provider_config.model = creds.model
			end

			local first_comment = buffer.find_first_comment_line(bufnr)
			local tw = typewriter.new({
				bufnr = bufnr,
				first_comment_line = first_comment,
				interval_ms = 12,
				chars_per_tick = 4,
				on_update = function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						expected_changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
					end
				end,
			})
			local has_content = false

			state.stream_handle = provider.generate(final_prompt, provider_config, function(chunk)
				if should_abort_for_buffer_changes() then
					tw:stop()
					return abort_due_to_buffer_changes("Commit buffer changed during generation")
				end

				has_content = true
				tw:push(chunk)
			end, function()
				tw:finish(function()
					if should_abort_for_buffer_changes() then
						return abort_due_to_buffer_changes("Commit buffer changed during generation")
					end

					state.stream_handle = nil
					state.generating = false
					if not has_content then
						if not silent then
							vim.notify("No message content received from provider", vim.log.levels.WARN)
						end
						return
					end

					if vim.api.nvim_buf_is_valid(bufnr) then
						state.generated = true
					end

					if not silent then
						vim.notify("Commit message generated!", vim.log.levels.INFO)
					end
				end)
			end, function(gen_err)
				if state.stream_handle and state.stream_handle.canceled then
					state.stream_handle = nil
					state.generating = false
					return
				end

				state.stream_handle = nil
				tw:stop()
				fail("Error: " .. gen_err)
			end)
		end)
	end)
end

---@param extra_context? string
function M.generate(extra_context)
	if not buffer.is_gitcommit_buffer() then
		vim.notify("Not in a gitcommit buffer", vim.log.levels.WARN)
		return
	end

	local ok, err = config.validate_provider()
	if not ok then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end

	if not providers.has_current_credentials() then
		vim.notify("Provider is not configured or authenticated. Run :AICommit status", vim.log.levels.WARN)
		return
	end

	local languages = config.get().languages

	if #languages == 0 then
		vim.notify("No languages configured. Add languages to your config.", vim.log.levels.WARN)
		return
	end

	if #languages == 1 then
		M.run(languages[1], extra_context)
		return
	end

	vim.ui.select(languages, { prompt = "Select language:" }, function(choice)
		if not choice then
			return
		end
		M.run(choice, extra_context)
	end)
end

return M
