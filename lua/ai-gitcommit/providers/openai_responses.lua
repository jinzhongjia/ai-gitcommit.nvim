local openai_compat = require("ai-gitcommit.providers.openai_compat")

local M = {}

---@class AIGitCommit.OpenAIResponsesOpts
---@field build_headers fun(config: AIGitCommit.ProviderConfig): table<string, string>
---@field map_error? fun(err: string): string

---@param prompt string
---@param config AIGitCommit.ProviderConfig
---@param opts AIGitCommit.OpenAIResponsesOpts
---@param on_chunk fun(content: string)
---@param on_done fun()
---@param on_error fun(err: string)
---@return AIGitCommit.StreamHandle?
function M.generate(prompt, config, opts, on_chunk, on_done, on_error)
	local body = {
		model = config.model,
		input = {
			{ role = "user", content = prompt },
		},
		stream = true,
		store = false,
		max_output_tokens = config.max_tokens or 500,
	}
	local failed = false

	---@param err string
	local function fail(err)
		if failed then
			return
		end
		failed = true
		on_error(err)
	end

	return openai_compat.request(config, opts, body, function(chunk)
		if failed then
			return
		end
		if chunk.type == "response.failed" or chunk.type == "response.incomplete" then
			local response = chunk.response or {}
			local err = response.error
			local message = type(err) == "table" and err.message or err
			if type(message) ~= "string" then
				local details = response.incomplete_details
				local reason = type(details) == "table" and details.reason or nil
				message = type(reason) == "string" and ("Response incomplete: " .. reason)
					or "Response generation failed"
			end
			fail(opts.map_error and opts.map_error(message) or message)
		elseif chunk.type == "response.output_text.delta" then
			local delta = chunk.delta
			if type(delta) == "string" and delta ~= "" then
				on_chunk(delta)
			end
		end
	end, function()
		if not failed then
			on_done()
		end
	end, fail)
end

return M
