local openai_compat = require("ai-gitcommit.providers.openai_compat")
local openai_responses = require("ai-gitcommit.providers.openai_responses")

local M = {}
local version = vim.version()

---@param err string
---@return string
local function map_copilot_error(err)
	local msg = err or ""
	local lowered = msg:lower()

	if
		lowered:find("access to this endpoint is forbidden", 1, true)
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

---@param config AIGitCommit.ProviderConfig
---@return table<string, string>
local function build_headers(config)
	return {
		["Content-Type"] = "application/json",
		["Authorization"] = "Bearer " .. config.api_key,
		["Copilot-Integration-Id"] = "vscode-chat",
		["Editor-Version"] = string.format("Neovim/%d.%d.%d", version.major, version.minor, version.patch),
		["Editor-Plugin-Version"] = "ai-gitcommit.nvim/0.1.0",
		["User-Agent"] = "ai-gitcommit.nvim",
	}
end

---@param endpoint string?
---@return boolean
local function is_responses_endpoint(endpoint)
	if type(endpoint) ~= "string" then
		return false
	end
	-- Match `/responses` or `/responses?...` / `/responses#...`, but not
	-- `/chat/completions` (which also ends with the word "completions").
	return endpoint:match("/responses$") ~= nil or endpoint:match("/responses[?#]") ~= nil
end

---@param prompt string
---@param config AIGitCommit.ProviderConfig
---@param on_chunk fun(content: string)
---@param on_done fun()
---@param on_error fun(err: string)
---@return AIGitCommit.StreamHandle?
function M.generate(prompt, config, on_chunk, on_done, on_error)
	if is_responses_endpoint(config.endpoint) then
		return openai_responses.generate(prompt, config, {
			build_headers = build_headers,
			map_error = map_copilot_error,
		}, on_chunk, on_done, on_error)
	end

	return openai_compat.generate(prompt, config, {
		build_headers = build_headers,
		map_error = map_copilot_error,
		default_stream_options = false,
	}, on_chunk, on_done, on_error)
end

---@param _ AIGitCommit.ProviderConfig
---@return boolean
function M.has_credentials(_)
	local auth = require("ai-gitcommit.auth")
	return auth.is_authenticated("copilot")
end

---@param config AIGitCommit.ProviderConfig
---@return string
function M.credential_status(config)
	return M.has_credentials(config) and "authenticated" or "not authenticated"
end

---@param endpoint_base string?
---@param endpoint_kind "chat"|"responses"
---@param fallback_endpoint string?
---@return string?
local function build_endpoint(endpoint_base, endpoint_kind, fallback_endpoint)
	if endpoint_base and endpoint_base ~= "" then
		if endpoint_kind == "responses" then
			return endpoint_base .. "/responses"
		end
		return endpoint_base .. "/chat/completions"
	end
	-- No base from the token response → fall back to whatever the chat
	-- endpoint was, rewriting the suffix if needed.
	if not fallback_endpoint then
		return nil
	end
	if endpoint_kind == "responses" then
		local rewritten, replaced = fallback_endpoint:gsub("/chat/completions(/?)$", "/responses")
		if replaced > 0 then
			return rewritten
		end
		return fallback_endpoint
	end
	return fallback_endpoint
end

---@param config AIGitCommit.ProviderConfig
---@param callback fun(creds?: AIGitCommit.Credentials, err?: string)
function M.resolve_credentials(config, callback)
	local auth = require("ai-gitcommit.auth")
	auth.get_token("copilot", function(token_data, err)
		if err then
			callback(nil, "Auth error: " .. err)
			return
		end

		---@type AIGitCommit.Credentials
		local creds = {
			api_key = token_data.token,
			endpoint = token_data.endpoint,
		}

		-- User pinned a model explicitly → use it. We assume /chat/completions
		-- unless the user also set providers.copilot.endpoint to a /responses URL.
		if type(config.model) == "string" and config.model ~= "" then
			callback(creds, nil)
			return
		end

		-- Otherwise resolve a default from Copilot's /models endpoint and
		-- route to the matching transport.
		local copilot_auth = require("ai-gitcommit.auth.copilot")
		copilot_auth.fetch_models(function(entries, models_err)
			if models_err then
				callback(nil, "Failed to resolve Copilot model: " .. models_err)
				return
			end
			local entry = entries[1]
			creds.model = entry.id
			creds.endpoint = build_endpoint(token_data.endpoint_base, entry.endpoint, token_data.endpoint)
			callback(creds, nil)
		end)
	end)
end

return M
