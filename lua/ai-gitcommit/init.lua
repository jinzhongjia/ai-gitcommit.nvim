local config = require("ai-gitcommit.config")
local git = require("ai-gitcommit.git")
local buffer = require("ai-gitcommit.buffer")
local context = require("ai-gitcommit.context")
local prompt = require("ai-gitcommit.prompt")
local providers = require("ai-gitcommit.providers")
local auth = require("ai-gitcommit.auth")

local M = {}

local subcommands = { "login", "logout", "status" }

local generated_buffers = {}
local generating_buffers = {}
local debounce_timers = {}

local function has_api_key()
	local api_key = config.get().api_key
	if type(api_key) == "function" then
		api_key = api_key()
	end
	return api_key ~= nil and api_key ~= ""
end

---@param args string
---@return string?, string?
local function parse_subcommand(args)
	if args == "" then
		return nil, nil
	end

	local parts = vim.split(args, "%s+", { trimempty = true })
	local first = parts[1]

	for _, sub in ipairs(subcommands) do
		if first == sub then
			return sub, parts[2]
		end
	end

	return nil, args
end

local function do_login()
	vim.notify("Starting Anthropic OAuth flow...", vim.log.levels.INFO)
	auth.login(function(success, err)
		if success then
			vim.notify("Logged in to Anthropic", vim.log.levels.INFO)
		else
			vim.notify("Login failed: " .. (err or "unknown"), vim.log.levels.ERROR)
		end
	end)
end

local function do_logout()
	auth.logout()
	vim.notify("Logged out from Anthropic", vim.log.levels.INFO)
end

local function do_status()
	local status = auth.is_authenticated() and "authenticated" or "not authenticated"
	vim.notify("Anthropic: " .. status, vim.log.levels.INFO)
end

---@param language string
---@param extra_context? string
---@param bufnr? number
---@param silent? boolean
local function do_generate(language, extra_context, bufnr, silent)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if generating_buffers[bufnr] then
		return
	end

	generating_buffers[bufnr] = true

	if not silent then
		vim.notify("Generating commit message...", vim.log.levels.INFO)
	end

	git.get_staged_diff(function(diff)
		git.get_staged_files(function(files)
			if diff == "" then
				generating_buffers[bufnr] = nil
				if not silent then
					vim.notify("No staged changes found", vim.log.levels.WARN)
				end
				return
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

			local function run_generate(api_key)
				local provider_config = config.get_provider()
				provider_config.api_key = api_key

				local provider = providers.get()
				local message = ""

				provider.generate(final_prompt, provider_config, function(chunk)
					message = message .. chunk
					if vim.api.nvim_buf_is_valid(bufnr) then
						buffer.set_commit_message(message, bufnr)
					end
				end, function()
					generating_buffers[bufnr] = nil
					generated_buffers[bufnr] = true
					if not silent then
						vim.notify("Commit message generated!", vim.log.levels.INFO)
					end
				end, function(gen_err)
					generating_buffers[bufnr] = nil
					if not silent then
						vim.notify("Error: " .. gen_err, vim.log.levels.ERROR)
					end
				end)
			end

			local api_key = cfg.api_key
			if type(api_key) == "function" then
				api_key = api_key()
			end

			if api_key then
				run_generate(api_key)
			else
				auth.get_token(function(token_data, err)
					if err then
						generating_buffers[bufnr] = nil
						if not silent then
							vim.notify("Auth error: " .. err, vim.log.levels.ERROR)
						end
						return
					end
					run_generate(token_data.token)
				end)
			end
		end)
	end)
end

---@param opts? AIGitCommit.Config
function M.setup(opts)
	config.setup(opts)

	vim.api.nvim_create_user_command("AICommit", function(cmd_opts)
		local sub, arg = parse_subcommand(cmd_opts.args)

		if sub == "login" then
			do_login()
		elseif sub == "logout" then
			do_logout()
		elseif sub == "status" then
			do_status()
		else
			M.generate(arg)
		end
	end, {
		nargs = "*",
		complete = function(_, line)
			local parts = vim.split(line, "%s+", { trimempty = true })
			if #parts == 1 then
				return { "login", "logout", "status" }
			elseif #parts == 2 then
				local matches = {}
				for _, sub in ipairs(subcommands) do
					if sub:find("^" .. parts[2]) then
						table.insert(matches, sub)
					end
				end
				return matches
			end
			return {}
		end,
		desc = "AI commit message generator",
	})

	local keymap = config.get().keymap
	if keymap then
		vim.keymap.set("n", keymap, function()
			M.generate()
		end, { desc = "AI Generate Commit Message" })
	end

	local auto_cfg = config.get().auto
	if auto_cfg and auto_cfg.enabled then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "gitcommit",
			callback = function(args)
				local bufnr = args.buf
				local debounce_ms = auto_cfg.debounce_ms or 300

				if debounce_timers[bufnr] then
					pcall(function()
						debounce_timers[bufnr]:stop()
						debounce_timers[bufnr]:close()
					end)
				end

				debounce_timers[bufnr] = vim.defer_fn(function()
					debounce_timers[bufnr] = nil

					if not vim.api.nvim_buf_is_valid(bufnr) then
						return
					end

					if generated_buffers[bufnr] or generating_buffers[bufnr] then
						return
					end

					if not has_api_key() and not auth.is_authenticated() then
						return
					end

					local languages = config.get().languages

					if #languages == 1 then
						do_generate(languages[1], nil, bufnr, true)
						return
					end

					vim.ui.select(languages, { prompt = "Select language:" }, function(choice)
						if not choice then
							return
						end
						do_generate(choice, nil, bufnr, true)
					end)
				end, debounce_ms)
			end,
		})
	end

	vim.api.nvim_create_autocmd("BufDelete", {
		callback = function(args)
			local bufnr = args.buf
			generated_buffers[bufnr] = nil
			generating_buffers[bufnr] = nil
			if debounce_timers[bufnr] then
				debounce_timers[bufnr]:stop()
				debounce_timers[bufnr]:close()
				debounce_timers[bufnr] = nil
			end
		end,
	})
end

---@param extra_context? string
function M.generate(extra_context)
	if not buffer.is_gitcommit_buffer() then
		vim.notify("Not in a gitcommit buffer", vim.log.levels.WARN)
		return
	end

	if not has_api_key() and not auth.is_authenticated() then
		vim.notify("Not authenticated. Run :AICommit login", vim.log.levels.WARN)
		return
	end

	local languages = config.get().languages

	if #languages == 1 then
		do_generate(languages[1], extra_context)
		return
	end

	vim.ui.select(languages, { prompt = "Select language:" }, function(choice)
		if not choice then
			return
		end
		do_generate(choice, extra_context)
	end)
end

return M
