local stream = require("ai-gitcommit.stream")

local M = {}
local version = vim.version()

---@param err string
---@return string
local function map_copilot_error(err)
	local msg = err or ""
	local lowered = msg:lower()

	if lowered:find("access to this endpoint is forbidden", 1, true)
		or lowered:find("forbidden", 1, true)
		or lowered:find("403", 1, true)
	then
		return "GitHub Copilot request was forbidden (403). "
			.. "Verify this account has Copilot access and that copilot.vim or copilot.lua is authenticated."
	end

	if lowered:find("404", 1, true) or lowered:find("not found", 1, true) then
		return "GitHub Copilot endpoint not found. Check providers.copilot.endpoint "
			.. "(recommended: https://api.githubcopilot.com/chat/completions)."
	end

	return msg
end

---@param prompt string
---@param config AIGitCommit.ProviderConfig
---@param on_chunk fun(content: string)
---@param on_done fun()
---@param on_error fun(err: string)
function M.generate(prompt, config, on_chunk, on_done, on_error)
	local body = {
		model = config.model,
		max_tokens = config.max_tokens or 500,
		messages = {
			{ role = "system", content = "You are a git commit message generator. You analyze code diffs and produce well-structured conventional commit messages with a subject line and descriptive body." },
			{ role = "user", content = prompt },
		},
		stream = true,
	}

	stream.request({
		url = config.endpoint,
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. config.api_key,
			["Copilot-Integration-Id"] = "vscode-chat",
			["Editor-Version"] = string.format("Neovim/%d.%d.%d", version.major, version.minor, version.patch),
			["Editor-Plugin-Version"] = "ai-gitcommit.nvim/0.1.0",
			["User-Agent"] = "ai-gitcommit.nvim",
		},
		body = body,
	}, function(chunk)
		if chunk.choices and chunk.choices[1] and chunk.choices[1].delta then
			local content = chunk.choices[1].delta.content
			if type(content) == "string" and content ~= "" then
				on_chunk(content)
			end
		end
	end, on_done, function(err)
		on_error(map_copilot_error(err))
	end)
end

return M
