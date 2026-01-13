local stream = require("ai-gitcommit.stream")

local M = {}

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
			{ role = "user", content = prompt },
		},
		stream = true,
	}

	stream.request({
		url = config.endpoint,
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["x-api-key"] = config.api_key,
			["anthropic-version"] = "2023-06-01",
		},
		body = body,
	}, function(chunk)
		if chunk.type == "content_block_delta" and chunk.delta then
			local text = chunk.delta.text
			if text then
				on_chunk(text)
			end
		end
	end, on_done, on_error)
end

return M
