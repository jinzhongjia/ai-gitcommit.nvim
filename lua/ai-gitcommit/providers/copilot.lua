local stream = require("ai-gitcommit.stream")

local M = {}

local COPILOT_CHAT_URL = "https://api.githubcopilot.com/chat/completions"

---@param prompt string
---@param config AIGitCommit.ProviderConfig
---@param on_chunk fun(content: string)
---@param on_done fun()
---@param on_error fun(err: string)
function M.generate(prompt, config, on_chunk, on_done, on_error)
	local body = {
		model = config.model or "gpt-4o",
		messages = {
			{ role = "user", content = prompt },
		},
		max_tokens = config.max_tokens or 500,
		temperature = 0.3,
		stream = true,
	}

	local nvim_version = vim.version()

	stream.request({
		url = COPILOT_CHAT_URL,
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. config.token,
			["Editor-Version"] = string.format(
				"Neovim/%d.%d.%d",
				nvim_version.major,
				nvim_version.minor,
				nvim_version.patch
			),
			["Copilot-Integration-Id"] = "vscode-chat",
		},
		body = body,
	}, function(chunk)
		local content = chunk.choices and chunk.choices[1] and chunk.choices[1].delta and chunk.choices[1].delta.content
		if content then
			on_chunk(content)
		end
	end, on_done, on_error)
end

return M
