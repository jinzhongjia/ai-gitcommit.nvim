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
			["Authorization"] = "Bearer " .. config.api_key,
		},
		body = body,
	}, function(chunk)
		if chunk.choices and chunk.choices[1] and chunk.choices[1].delta then
			local content = chunk.choices[1].delta.content
			if type(content) == "string" and content ~= "" then
				on_chunk(content)
			end
		end
	end, on_done, on_error)
end

return M
