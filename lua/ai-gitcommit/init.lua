local buffer = require("ai-gitcommit.buffer")
local config = require("ai-gitcommit.config")
local git = require("ai-gitcommit.git")
local prompt = require("ai-gitcommit.prompt")
local context = require("ai-gitcommit.context")
local providers = require("ai-gitcommit.providers")
local auth = require("ai-gitcommit.auth")
local typewriter = require("ai-gitcommit.typewriter")

local M = {}

local subcommands = { "login", "logout", "status" }
local provider_names = { "openai", "anthropic", "copilot" }

local generated_buffers = {}
local generating_buffers = {}
local debounce_timers = {}

---@param api_key string|fun():string|nil
---@return string?
local function resolve_api_key(api_key)
	if type(api_key) == "function" then
		api_key = api_key()
	end

	if type(api_key) ~= "string" or api_key == "" then
		return nil
	end

	return api_key
end

---@param provider_config AIGitCommit.ProviderConfig|AIGitCommit.CopilotProviderConfig
---@return boolean
local function openai_requires_api_key(provider_config)
	return provider_config.api_key_required ~= false
end

---@return boolean
local function has_provider_credentials()
	local provider, _ = config.get_provider()
	if not provider then
		return false
	end

	if provider.name == "openai" then
		if not openai_requires_api_key(provider.config) then
			return true
		end
		return resolve_api_key(provider.config.api_key) ~= nil
	end

	if provider.name == "anthropic" then
		if resolve_api_key(provider.config.api_key) ~= nil then
			return true
		end
		return auth.is_authenticated("anthropic")
	end

	if provider.name == "copilot" then
		return auth.is_authenticated("copilot")
	end

	return false
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

---@param provider string?
local function do_login(provider)
	if not provider then
		vim.notify("Usage: :AICommit login <provider>", vim.log.levels.ERROR)
		return
	end

	if not config.is_supported_provider(provider) then
		vim.notify("Unsupported provider: " .. provider, vim.log.levels.ERROR)
		return
	end

	vim.notify("Starting " .. provider .. " login flow...", vim.log.levels.INFO)
	auth.login(provider, function(result, err)
		if result then
			vim.notify("Logged in to " .. provider, vim.log.levels.INFO)
		else
			vim.notify("Login failed: " .. (err or "unknown"), vim.log.levels.ERROR)
		end
	end)
end

---@param provider string?
local function do_logout(provider)
	if not provider then
		vim.notify("Usage: :AICommit logout <provider>", vim.log.levels.ERROR)
		return
	end

	if not config.is_supported_provider(provider) then
		vim.notify("Unsupported provider: " .. provider, vim.log.levels.ERROR)
		return
	end

	local ok, err = auth.logout(provider)
	if not ok then
		vim.notify("Logout failed: " .. (err or "unknown"), vim.log.levels.ERROR)
		return
	end

	vim.notify("Logged out from " .. provider, vim.log.levels.INFO)
end

---@param provider string
---@return string
local function provider_status(provider)
	if provider == "openai" then
		local provider_info, _ = config.get_provider()
		local openai_config = provider_info and provider_info.name == "openai" and provider_info.config
			or config.get().providers.openai
		if openai_config and not openai_requires_api_key(openai_config) then
			return "configured"
		end
		local has_key = openai_config and resolve_api_key(openai_config.api_key) ~= nil
		return has_key and "configured" or "not configured"
	end

	local status = auth.is_authenticated(provider) and "authenticated" or "not authenticated"
	return status
end

---@param provider string?
local function do_status(provider)
	if provider then
		if not config.is_supported_provider(provider) then
			vim.notify("Unsupported provider: " .. provider, vim.log.levels.ERROR)
			return
		end
		vim.notify(provider .. ": " .. provider_status(provider), vim.log.levels.INFO)
		return
	end

	for _, name in ipairs(provider_names) do
		vim.notify(name .. ": " .. provider_status(name), vim.log.levels.INFO)
	end
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

			local function run_generate(api_key, endpoint_override)
				local provider_info, provider_err = config.get_provider()
				if not provider_info then
					generating_buffers[bufnr] = nil
					if not silent then
						vim.notify(provider_err, vim.log.levels.ERROR)
					end
					return
				end

				local provider_config = vim.deepcopy(provider_info.config)
				if api_key then
					provider_config.api_key = api_key
				end
				if endpoint_override then
					provider_config.endpoint = endpoint_override
				end

				local provider = providers.get(provider_info.name)
				local first_comment = buffer.find_first_comment_line(bufnr)

				local tw = typewriter.new({
					bufnr = bufnr,
					first_comment_line = first_comment,
					interval_ms = 12,
					chars_per_tick = 4,
				})

				provider.generate(final_prompt, provider_config, function(chunk)
					tw:push(chunk)
				end, function()
					tw:finish(function()
						generating_buffers[bufnr] = nil
						generated_buffers[bufnr] = true
						if not silent then
							vim.notify("Commit message generated!", vim.log.levels.INFO)
						end
					end)
				end, function(gen_err)
					tw:stop()
					generating_buffers[bufnr] = nil
					if not silent then
						vim.notify("Error: " .. gen_err, vim.log.levels.ERROR)
					end
				end)
			end

			local provider_info, provider_err = config.get_provider()
			if not provider_info then
				generating_buffers[bufnr] = nil
				if not silent then
					vim.notify(provider_err, vim.log.levels.ERROR)
				end
				return
			end

			local api_key = resolve_api_key(provider_info.config.api_key)

			if provider_info.name == "openai" then
				if openai_requires_api_key(provider_info.config) and not api_key then
					generating_buffers[bufnr] = nil
					if not silent then
						vim.notify("OpenAI API key not configured", vim.log.levels.ERROR)
					end
					return
				end
				run_generate(api_key)
				return
			end

			if provider_info.name == "anthropic" and api_key then
				run_generate(api_key)
				return
			end

			auth.get_token(provider_info.name, function(token_data, err)
				if err then
					generating_buffers[bufnr] = nil
					if not silent then
						vim.notify("Auth error: " .. err, vim.log.levels.ERROR)
					end
					return
				end
				run_generate(token_data.token, token_data.endpoint)
			end)
		end)
	end)
end

---@param opts? AIGitCommit.Config
function M.setup(opts)
	config.setup(opts)

	vim.api.nvim_create_user_command("AICommit", function(cmd_opts)
		local sub, arg = parse_subcommand(cmd_opts.args)

		if sub == "login" then
			do_login(arg)
		elseif sub == "logout" then
			do_logout(arg)
		elseif sub == "status" then
			do_status(arg)
		else
			M.generate(arg)
		end
	end, {
		nargs = "*",
		complete = function(_, line)
			local parts = vim.split(line, "%s+", { trimempty = true })
			local has_trailing_space = line:match("%s$") ~= nil

			if #parts == 1 then
				return { "login", "logout", "status" }
			elseif #parts == 2 then
				if has_trailing_space and (parts[2] == "login" or parts[2] == "logout" or parts[2] == "status") then
					return provider_names
				end

				local matches = {}
				for _, sub in ipairs(subcommands) do
					if sub:find("^" .. parts[2]) then
						table.insert(matches, sub)
					end
				end
				return matches
			elseif #parts == 3 and (parts[2] == "login" or parts[2] == "logout" or parts[2] == "status") then
				if has_trailing_space then
					return {}
				end

				local matches = {}
				for _, name in ipairs(provider_names) do
					if name:find("^" .. parts[3]) then
						table.insert(matches, name)
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

					if not has_provider_credentials() then
						return
					end

					local languages = config.get().languages

					if #languages == 1 then
						do_generate(languages[1], nil, bufnr, false)
						return
					end

					vim.ui.select(languages, { prompt = "Select language:" }, function(choice)
						if not choice then
							return
						end
						do_generate(choice, nil, bufnr, false)
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

	local ok, err = config.validate_provider()
	if not ok then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end

	if not has_provider_credentials() then
		vim.notify("Provider is not configured or authenticated. Run :AICommit status", vim.log.levels.WARN)
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
