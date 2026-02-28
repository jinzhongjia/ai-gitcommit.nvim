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

	if config.stream_options ~= false then
		body.stream_options = { include_usage = true }
	end

	local headers = {
		["Content-Type"] = "application/json",
	}

	if type(config.api_key) == "string" and config.api_key ~= "" then
		local header_name = config.api_key_header or "Authorization"
		local prefix = config.api_key_prefix or "Bearer "
		headers[header_name] = prefix .. config.api_key
	end

	for key, value in pairs(config.extra_headers or {}) do
		headers[key] = value
	end

	stream.request({
		url = config.endpoint,
		method = "POST",
		headers = headers,
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
