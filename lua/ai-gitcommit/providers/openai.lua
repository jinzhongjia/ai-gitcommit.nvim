local openai_compat = require("ai-gitcommit.providers.openai_compat")

local M = {}

---@param api_key string|fun():string|nil
---@return string?
local function resolve_api_key(api_key)
	if type(api_key) == "function" then
		api_key = api_key()
	end
	if type(api_key) ~= "string" or api_key == "" then
		return nil
	end
	return api_key
end

---@param config AIGitCommit.ProviderConfig
---@return boolean
local function requires_api_key(config)
	return config.api_key_required ~= false
end

---@param config AIGitCommit.ProviderConfig
---@return table<string, string>
local function build_headers(config)
	local headers = { ["Content-Type"] = "application/json" }

	if type(config.api_key) == "string" and config.api_key ~= "" then
		local header_name = config.api_key_header or "Authorization"
		local prefix = config.api_key_prefix or "Bearer "
		headers[header_name] = prefix .. config.api_key
	end

	return headers
end

---@param prompt string
---@param config AIGitCommit.ProviderConfig
---@param on_chunk fun(content: string)
---@param on_done fun()
---@param on_error fun(err: string)
---@return AIGitCommit.StreamHandle?
function M.generate(prompt, config, on_chunk, on_done, on_error)
	return openai_compat.generate(prompt, config, {
		build_headers = build_headers,
		default_stream_options = true,
	}, on_chunk, on_done, on_error)
end

---@param config AIGitCommit.ProviderConfig
---@return boolean
function M.has_credentials(config)
	if not requires_api_key(config) then
		return true
	end
	return resolve_api_key(config.api_key) ~= nil
end

---@param config AIGitCommit.ProviderConfig
---@return string
function M.credential_status(config)
	return M.has_credentials(config) and "configured" or "not configured"
end

---@param config AIGitCommit.ProviderConfig
---@param callback fun(creds?: AIGitCommit.Credentials, err?: string)
function M.resolve_credentials(config, callback)
	local api_key = resolve_api_key(config.api_key)
	if requires_api_key(config) and not api_key then
		callback(nil, "OpenAI API key not configured")
		return
	end
	callback({ api_key = api_key or "" }, nil)
end

return M
