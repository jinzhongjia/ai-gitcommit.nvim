local stream = require("ai-gitcommit.stream")

local M = {}

---@class AIGitCommit.OpenAICompatOpts
---@field build_headers fun(config: AIGitCommit.ProviderConfig): table<string, string>
---@field map_error? fun(err: string): string
---@field default_stream_options? boolean

---@param config AIGitCommit.ProviderConfig
---@param default_stream_options boolean?
---@return boolean
local function should_include_stream_options(config, default_stream_options)
	if config.stream_options ~= nil then
		return config.stream_options ~= false
	end
	return default_stream_options ~= false
end

---@param prompt string
---@param config AIGitCommit.ProviderConfig
---@param opts AIGitCommit.OpenAICompatOpts
---@param on_chunk fun(content: string)
---@param on_done fun()
---@param on_error fun(err: string)
---@return AIGitCommit.StreamHandle?
function M.generate(prompt, config, opts, on_chunk, on_done, on_error)
	local body = {
		model = config.model,
		max_tokens = config.max_tokens or 500,
		messages = {
			{ role = "user", content = prompt },
		},
		stream = true,
	}

	if should_include_stream_options(config, opts.default_stream_options) then
		body.stream_options = { include_usage = true }
	end

	local headers = opts.build_headers(config)
	if headers["Content-Type"] == nil then
		headers["Content-Type"] = "application/json"
	end

	for key, value in pairs(config.extra_headers or {}) do
		headers[key] = value
	end

	local error_cb = on_error
	if opts.map_error then
		error_cb = function(err)
			on_error(opts.map_error(err))
		end
	end

	return stream.request({
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
	end, on_done, error_cb)
end

return M
