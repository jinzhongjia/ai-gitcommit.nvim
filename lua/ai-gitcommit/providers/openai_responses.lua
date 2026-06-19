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

	return openai_compat.request(config, opts, body, function(chunk)
		-- Reference event schema:
		-- https://platform.openai.com/docs/api-reference/responses-streaming
		-- response.completed is the terminator; text was streamed via deltas.
		if chunk.type == "response.output_text.delta" then
			local delta = chunk.delta
			if type(delta) == "string" and delta ~= "" then
				on_chunk(delta)
			end
		end
	end, on_done, on_error)
end

return M
