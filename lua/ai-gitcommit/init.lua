local config = require("ai-gitcommit.config")
local git = require("ai-gitcommit.git")
local buffer = require("ai-gitcommit.buffer")
local context = require("ai-gitcommit.context")
local prompt = require("ai-gitcommit.prompt")
local providers = require("ai-gitcommit.providers")

local M = {}

local subcommands = { "login", "logout", "status" }

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

---@param provider_name string
local function do_login(provider_name)
	if not provider_name or provider_name == "" then
		vim.notify("Usage: :AICommit login <provider>", vim.log.levels.ERROR)
		return
	end

	if not config.requires_oauth(provider_name) then
		vim.notify(provider_name .. " uses API key, not OAuth", vim.log.levels.INFO)
		return
	end

	local auth = require("ai-gitcommit.auth")
	vim.notify("Starting OAuth flow for " .. provider_name .. "...", vim.log.levels.INFO)
	auth.login(provider_name, function(success, err)
		if success then
			vim.notify("Logged in to " .. provider_name, vim.log.levels.INFO)
		else
			vim.notify("Login failed: " .. (err or "unknown"), vim.log.levels.ERROR)
		end
	end)
end

---@param provider_name string
local function do_logout(provider_name)
	if not provider_name or provider_name == "" then
		vim.notify("Usage: :AICommit logout <provider>", vim.log.levels.ERROR)
		return
	end

	if not config.requires_oauth(provider_name) then
		vim.notify(provider_name .. " does not use OAuth", vim.log.levels.INFO)
		return
	end

	local auth = require("ai-gitcommit.auth")
	auth.logout(provider_name)
	vim.notify("Logged out from " .. provider_name, vim.log.levels.INFO)
end

local function do_status()
	local auth = require("ai-gitcommit.auth")
	local oauth_providers = { "copilot", "codex", "claude" }
	local lines = { "OAuth Status:" }

	for _, name in ipairs(oauth_providers) do
		local status = auth.is_authenticated(name) and "authenticated" or "not authenticated"
		table.insert(lines, string.format("  %s: %s", name, status))
	end

	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
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
			do_status()
		else
			M.generate(arg)
		end
	end, {
		nargs = "*",
		complete = function(_, line)
			local parts = vim.split(line, "%s+", { trimempty = true })
			if #parts == 1 then
				return vim.list_extend({ "login", "logout", "status" }, {})
			elseif #parts == 2 and (parts[2] == "login" or parts[2] == "logout") then
				return { "copilot", "codex", "claude" }
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
end

---@param extra_context? string
function M.generate(extra_context)
	if not buffer.is_gitcommit_buffer() then
		vim.notify("Not in a gitcommit buffer", vim.log.levels.WARN)
		return
	end

	local cfg = config.get()
	local provider_name = cfg.provider
	local provider = providers.get(provider_name)

	if not provider then
		vim.notify("Provider not found: " .. provider_name, vim.log.levels.ERROR)
		return
	end

	if config.requires_oauth(provider_name) then
		local auth = require("ai-gitcommit.auth")
		if not auth.is_authenticated(provider_name) then
			vim.notify("Not authenticated. Run :AICommit login " .. provider_name, vim.log.levels.WARN)
			return
		end
	end

	vim.notify("Generating commit message...", vim.log.levels.INFO)

	git.get_staged_diff(function(diff)
		git.get_staged_files(function(files)
			if diff == "" then
				vim.notify("No staged changes found", vim.log.levels.WARN)
				return
			end

			local processed_diff = context.build_context(diff, files, cfg)

			local final_prompt = prompt.build({
				style = cfg.commit_style,
				language = cfg.language,
				extra_context = extra_context,
				files = files,
				diff = processed_diff,
			})

			local function do_generate(provider_config)
				local message = ""
				provider.generate(final_prompt, provider_config, function(chunk)
					message = message .. chunk
					buffer.set_commit_message(message)
				end, function()
					vim.notify("Commit message generated!", vim.log.levels.INFO)
				end, function(err)
					vim.notify("Error: " .. err, vim.log.levels.ERROR)
				end)
			end

			if config.requires_oauth(provider_name) then
				local auth = require("ai-gitcommit.auth")
				auth.get_token(provider_name, function(token_data, err)
					if err then
						vim.notify("Auth error: " .. err, vim.log.levels.ERROR)
						return
					end
					local provider_config = config.get_provider()
					provider_config.token = token_data.token
					do_generate(provider_config)
				end)
			else
				config.get_api_key(provider_name, function(api_key, err)
					if err then
						vim.notify("API key error: " .. err, vim.log.levels.ERROR)
						return
					end
					local provider_config = config.get_provider()
					provider_config.api_key = api_key
					do_generate(provider_config)
				end)
			end
		end)
	end)
end

return M
