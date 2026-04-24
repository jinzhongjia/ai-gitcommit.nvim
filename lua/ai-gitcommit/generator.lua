local buffer = require("ai-gitcommit.buffer")
local buffer_state = require("ai-gitcommit.buffer_state")
local config = require("ai-gitcommit.config")
local context = require("ai-gitcommit.context")
local git = require("ai-gitcommit.git")
local prompt = require("ai-gitcommit.prompt")
local providers = require("ai-gitcommit.providers")
local typewriter = require("ai-gitcommit.typewriter")

local M = {}

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

	local provider_info, provider_err = config.get_provider()
	if not provider_info then
		if not silent then
			vim.notify(provider_err, vim.log.levels.ERROR)
		end
		return
	end

	state.generating = true

	---@param msg string
	---@param level? integer
	local function fail(msg, level)
		state.generating = false
		if not silent then
			vim.notify(msg, level or vim.log.levels.ERROR)
		end
	end

	if not silent then
		vim.notify("Generating commit message...", vim.log.levels.INFO)
	end

	git.get_staged_diff(function(diff, diff_err)
		if diff_err then
			return fail("Error: " .. diff_err)
		end

		git.get_staged_files(function(files, files_err)
			if files_err then
				return fail("Error: " .. files_err)
			end

			if diff == "" then
				return fail("No staged changes found", vim.log.levels.WARN)
			end

			local cfg = config.get()
			local processed_diff = context.build_context(diff, cfg)

			local final_prompt = prompt.build({
				template = cfg.prompt_template,
				language = language,
				extra_context = extra_context,
				files = files,
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
				})
				local has_content = false

				provider.generate(final_prompt, provider_config, function(chunk)
					has_content = true
					tw:push(chunk)
				end, function()
					tw:finish(function()
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
					tw:stop()
					fail("Error: " .. gen_err)
				end)
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
