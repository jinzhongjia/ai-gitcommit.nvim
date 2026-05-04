local auth = require("ai-gitcommit.auth")
local config = require("ai-gitcommit.config")
local generator = require("ai-gitcommit.generator")
local providers = require("ai-gitcommit.providers")

local M = {}

local subcommands = { "logout", "status" }
local provider_names = { "openai", "copilot" }

---@param value string
---@param prefix string
---@return boolean
local function starts_with(value, prefix)
	return value:find(prefix, 1, true) == 1
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

---@param provider string?
local function do_status(provider)
	if provider then
		if not config.is_supported_provider(provider) then
			vim.notify("Unsupported provider: " .. provider, vim.log.levels.ERROR)
			return
		end
		vim.notify(provider .. ": " .. providers.status(provider), vim.log.levels.INFO)
		return
	end

	for _, name in ipairs(provider_names) do
		vim.notify(name .. ": " .. providers.status(name), vim.log.levels.INFO)
	end
end

---@param _ string
---@param line string
---@return string[]
local function complete(_, line)
	local parts = vim.split(line, "%s+", { trimempty = true })
	local has_trailing_space = line:match("%s$") ~= nil

	if #parts == 1 then
		return vim.deepcopy(subcommands)
	elseif #parts == 2 then
		if has_trailing_space and (parts[2] == "logout" or parts[2] == "status") then
			return provider_names
		end

		local matches = {}
		for _, sub in ipairs(subcommands) do
			if starts_with(sub, parts[2]) then
				table.insert(matches, sub)
			end
		end
		return matches
	elseif #parts == 3 and (parts[2] == "logout" or parts[2] == "status") then
		if has_trailing_space then
			return {}
		end

		local matches = {}
		for _, name in ipairs(provider_names) do
			if starts_with(name, parts[3]) then
				table.insert(matches, name)
			end
		end
		return matches
	end
	return {}
end

function M.setup()
	pcall(vim.api.nvim_del_user_command, "AICommit")

	vim.api.nvim_create_user_command("AICommit", function(cmd_opts)
		local sub, arg = parse_subcommand(cmd_opts.args)

		if sub == "logout" then
			do_logout(arg)
		elseif sub == "status" then
			do_status(arg)
		else
			generator.generate(arg)
		end
	end, {
		nargs = "*",
		complete = complete,
		desc = "AI commit message generator",
	})
end

return M
