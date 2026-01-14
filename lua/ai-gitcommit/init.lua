local config = require("ai-gitcommit.config")
local git = require("ai-gitcommit.git")
local buffer = require("ai-gitcommit.buffer")
local context = require("ai-gitcommit.context")
local prompt = require("ai-gitcommit.prompt")
local providers = require("ai-gitcommit.providers")
local auth = require("ai-gitcommit.auth")

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
end

---@param language string
---@param extra_context? string
local function do_generate(language, extra_context)
	vim.notify("Generating commit message...", vim.log.levels.INFO)

	git.get_staged_diff(function(diff)
		git.get_staged_files(function(files)
			if diff == "" then
				vim.notify("No staged changes found", vim.log.levels.WARN)
				return
			end

			local cfg = config.get()
			local processed_diff = context.build_context(diff, files, cfg)

			local final_prompt = prompt.build({
				style = cfg.commit_style,
				language = language,
				extra_context = extra_context,
				files = files,
				diff = processed_diff,
			})

			auth.get_token(function(token_data, err)
				if err then
					vim.notify("Auth error: " .. err, vim.log.levels.ERROR)
					return
				end

				local provider_config = config.get_provider()
				provider_config.api_key = token_data.token

				local provider = providers.get()
				local message = ""

				provider.generate(final_prompt, provider_config, function(chunk)
					message = message .. chunk
					buffer.set_commit_message(message)
				end, function()
					vim.notify("Commit message generated!", vim.log.levels.INFO)
				end, function(gen_err)
					vim.notify("Error: " .. gen_err, vim.log.levels.ERROR)
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

	if not auth.is_authenticated() then
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
