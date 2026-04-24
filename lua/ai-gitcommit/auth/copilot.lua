local fs = require("ai-gitcommit.util.fs")
local http = require("ai-gitcommit.util.http")

local M = {}

---@class AIGitCommit.CopilotTokenData
---@field token string
---@field expires_at? number
---@field endpoint? string

---@class AIGitCommit.CopilotTokenResult
---@field token string
---@field endpoint? string

---@class AIGitCommit.CopilotModelsCache
---@field ids string[]
---@field expires_at number

---@class AIGitCommit.CopilotTokenResponse
---@field token string
---@field expires_at? number
---@field endpoints? { api?: string }

local COPILOT_TOKEN_URL = "https://api.github.com/copilot_internal/v2/token"
local COPILOT_API_VERSION = "2025-10-01"
local MODELS_CACHE_TTL = 1800 -- 30 minutes
local IS_WINDOWS = vim.fn.has("win32") == 1

---@type string?
local _cached_oauth_token = nil
---@type AIGitCommit.CopilotTokenData?
local _cached_copilot_token = nil
local _token_refresh_in_progress = false
---@type fun(token_data?: AIGitCommit.CopilotTokenResult, err?: string)[]
local _pending_callbacks = {}
---@type fun(github_access_token: string, callback: fun(data?: AIGitCommit.CopilotTokenResponse, err?: string))?
local _mock_fetch_copilot_token = nil
---@type AIGitCommit.CopilotModelsCache?
local _cached_models = nil
---@type fun(copilot_token: string, endpoint: string, callback: fun(ids?: string[], err?: string))?
local _mock_fetch_models = nil

---@param stdout string
---@param fallback string
---@return string
local function decode_error(stdout, fallback)
	local ok, data = pcall(vim.json.decode, stdout)
	if ok and data then
		if data.error_description and data.error_description ~= "" then
			return data.error_description
		end
		if data.message and data.message ~= "" then
			return data.message
		end
		if data.error and type(data.error) == "string" and data.error ~= "" then
			return data.error
		end
	end

	local trimmed = vim.trim(stdout or "")
	if trimmed ~= "" then
		return trimmed
	end

	return fallback
end

--- Check if a curl exit code indicates an auth failure (HTTP 401/403)
--- curl --fail-with-body returns exit code 22 for HTTP errors;
--- we inspect stdout for status hints.
---@param exit_code integer
---@param stdout string
---@return boolean
local function is_auth_error(exit_code, stdout)
	if exit_code ~= 22 then
		return false
	end
	local lowered = (stdout or ""):lower()
	return lowered:find("401") ~= nil
		or lowered:find("unauthorized") ~= nil
		or lowered:find("403") ~= nil
		or lowered:find("forbidden") ~= nil
end

---@param github_access_token string
---@param callback fun(data?: AIGitCommit.CopilotTokenResponse, err?: string)
local function fetch_copilot_token(github_access_token, callback)
	if _mock_fetch_copilot_token then
		return _mock_fetch_copilot_token(github_access_token, callback)
	end

	http.curl({
		"-s",
		"-X",
		"GET",
		"--fail-with-body",
		"-H",
		"Accept: application/json",
		"-H",
		"User-Agent: ai-gitcommit.nvim",
		"-H",
		"Authorization: Bearer " .. github_access_token,
		COPILOT_TOKEN_URL,
	}, function(stdout, exit_code)
		if exit_code ~= 0 then
			if is_auth_error(exit_code, stdout) then
				_cached_oauth_token = nil
				_cached_copilot_token = nil
			end
			callback(nil, decode_error(stdout, "Failed to fetch GitHub Copilot token"))
			return
		end

		local ok, data = pcall(vim.json.decode, stdout)
		if not ok or not data then
			callback(nil, "Invalid Copilot token response")
			return
		end

		if not data.token or data.token == "" then
			local msg = data.message or data.error or "No Copilot token in response"
			callback(nil, msg)
			return
		end

		callback(data, nil)
	end)
end

--- Find the GitHub Copilot plugin config directory
---@return string
local function find_copilot_config_path()
	local xdg = os.getenv("XDG_CONFIG_HOME")
	if xdg and xdg ~= "" then
		return xdg
	end

	if IS_WINDOWS then
		local localappdata = os.getenv("LOCALAPPDATA")
		if localappdata and localappdata ~= "" then
			return localappdata
		end
	end

	return vim.fs.joinpath(os.getenv("HOME") or vim.fn.expand("~"), ".config")
end

--- Read OAuth token from installed Copilot plugin (copilot.vim / copilot.lua)
---@return string?
local function read_copilot_plugin_oauth_token()
	-- Check Codespaces environment
	local github_token = os.getenv("GITHUB_TOKEN")
	if github_token and github_token ~= "" and os.getenv("CODESPACES") then
		return github_token
	end

	local config_path = find_copilot_config_path()
	local copilot_dir = vim.fs.joinpath(config_path, "github-copilot")

	-- Try hosts.json first, then apps.json
	local files = { "hosts.json", "apps.json" }
	for _, filename in ipairs(files) do
		local filepath = vim.fs.joinpath(copilot_dir, filename)
		local content = fs.read_file(filepath)
		if content then
			local ok, data = pcall(vim.json.decode, content)
			if ok and data then
				for key, value in pairs(data) do
					if type(key) == "string" and key:find("github.com") and type(value) == "table" then
						local token = value.oauth_token
						if type(token) == "string" and token ~= "" then
							return token
						end
					end
				end
			end
		end
	end

	return nil
end

--- Resolve OAuth token: memory cache > Copilot plugin config
---@return string?
local function resolve_oauth_token()
	if _cached_oauth_token then
		return _cached_oauth_token
	end

	local plugin_token = read_copilot_plugin_oauth_token()
	if plugin_token then
		_cached_oauth_token = plugin_token
		return plugin_token
	end

	return nil
end

---@param token_data AIGitCommit.CopilotTokenData?
---@return boolean
local function is_copilot_token_valid(token_data)
	if not token_data or type(token_data.token) ~= "string" or token_data.token == "" then
		return false
	end

	if type(token_data.expires_at) ~= "number" then
		return true
	end

	return token_data.expires_at > (os.time() + 30)
end

--- Notify all pending callbacks and reset state
---@param token_data AIGitCommit.CopilotTokenResult?
---@param err string?
local function notify_pending_callbacks(token_data, err)
	local callbacks = _pending_callbacks
	_pending_callbacks = {}
	_token_refresh_in_progress = false

	for _, cb in ipairs(callbacks) do
		cb(token_data, err)
	end
end

--- Refresh copilot token using an OAuth token
---@param oauth_token string
---@param callback fun(token_data?: AIGitCommit.CopilotTokenResult, err?: string)
local function refresh_copilot_token(oauth_token, callback)
	fetch_copilot_token(oauth_token, function(copilot_data, token_err)
		if token_err then
			callback(nil, token_err)
			return
		end

		local endpoint = nil
		if copilot_data.endpoints and copilot_data.endpoints.api then
			endpoint = copilot_data.endpoints.api .. "/chat/completions"
		end

		_cached_copilot_token = {
			token = copilot_data.token,
			expires_at = copilot_data.expires_at,
			endpoint = endpoint,
		}

		callback({ token = copilot_data.token, endpoint = endpoint }, nil)
	end)
end

--- Get a valid Copilot token with concurrency protection
---@param oauth_token string
---@param callback fun(token_data?: AIGitCommit.CopilotTokenResult, err?: string)
local function get_valid_copilot_token(oauth_token, callback)
	if is_copilot_token_valid(_cached_copilot_token) then
		callback({ token = _cached_copilot_token.token, endpoint = _cached_copilot_token.endpoint }, nil)
		return
	end

	table.insert(_pending_callbacks, callback)

	if _token_refresh_in_progress then
		return
	end

	_token_refresh_in_progress = true

	refresh_copilot_token(oauth_token, function(token_data, err)
		notify_pending_callbacks(token_data, err)
	end)
end

---@return boolean
function M.is_authenticated()
	return resolve_oauth_token() ~= nil
end

---@param callback fun(token_data?: AIGitCommit.CopilotTokenResult, err?: string)
function M.get_token(callback)
	local oauth_token = resolve_oauth_token()
	if not oauth_token then
		callback(nil, "Not authenticated. Install copilot.vim or copilot.lua plugin")
		return
	end

	get_valid_copilot_token(oauth_token, callback)
end

---@param endpoint string
---@return string
local function models_url_from_chat_endpoint(endpoint)
	-- Derive the base from a chat completions endpoint like
	-- https://api.githubcopilot.com/chat/completions -> https://api.githubcopilot.com/models
	local base = endpoint:match("^(https?://[^/]+)")
	if base then
		return base .. "/models"
	end
	return "https://api.githubcopilot.com/models"
end

---@param model table
---@return number
local function model_multiplier(model)
	local billing = model.billing
	if type(billing) == "table" and type(billing.multiplier) == "number" then
		return billing.multiplier
	end
	-- Unknown cost → rank after known-cost models.
	return math.huge
end

--- Parse Copilot /models response and return chat-capable model IDs,
--- sorted by billing multiplier ascending (cheapest first). Ties preserve
--- the order returned by the API.
---@param body string
---@return string[]?, string?
local function parse_models_response(body)
	local ok, data = pcall(vim.json.decode, body)
	if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
		return nil, "Invalid /models response"
	end

	local entries = {}
	for idx, model in ipairs(data.data) do
		if type(model) == "table" and model.model_picker_enabled then
			local is_chat = true
			local caps = model.capabilities
			if type(caps) == "table" then
				local ctype = caps.type
				if type(ctype) == "string" then
					is_chat = ctype == "chat"
				elseif type(ctype) == "table" then
					is_chat = vim.tbl_contains(ctype, "chat")
				end
			end
			if is_chat and type(model.id) == "string" and model.id ~= "" then
				table.insert(entries, {
					id = model.id,
					multiplier = model_multiplier(model),
					order = idx,
				})
			end
		end
	end

	if #entries == 0 then
		return nil, "No usable chat models returned by Copilot"
	end

	table.sort(entries, function(a, b)
		if a.multiplier ~= b.multiplier then
			return a.multiplier < b.multiplier
		end
		return a.order < b.order
	end)

	local ids = {}
	for i, entry in ipairs(entries) do
		ids[i] = entry.id
	end
	return ids, nil
end

---@param copilot_token string
---@param endpoint string
---@param callback fun(ids?: string[], err?: string)
local function request_models(copilot_token, endpoint, callback)
	if _mock_fetch_models then
		return _mock_fetch_models(copilot_token, endpoint, callback)
	end

	http.curl({
		"-s",
		"-X",
		"GET",
		"--fail-with-body",
		"-H",
		"Accept: application/json",
		"-H",
		"User-Agent: ai-gitcommit.nvim",
		"-H",
		"Authorization: Bearer " .. copilot_token,
		"-H",
		"Copilot-Integration-Id: vscode-chat",
		"-H",
		"X-Github-Api-Version: " .. COPILOT_API_VERSION,
		models_url_from_chat_endpoint(endpoint),
	}, function(stdout, exit_code)
		if exit_code ~= 0 then
			callback(nil, decode_error(stdout, "Failed to fetch Copilot models"))
			return
		end
		local ids, err = parse_models_response(stdout)
		if err then
			callback(nil, err)
			return
		end
		callback(ids, nil)
	end)
end

---@param models AIGitCommit.CopilotModelsCache?
---@return boolean
local function is_models_cache_valid(models)
	return models ~= nil
		and type(models.ids) == "table"
		and #models.ids > 0
		and type(models.expires_at) == "number"
		and models.expires_at > os.time()
end

--- Fetch the list of Copilot model IDs available to the current account.
--- Results are cached in memory for 30 minutes.
---@param callback fun(ids?: string[], err?: string)
function M.fetch_models(callback)
	if is_models_cache_valid(_cached_models) then
		callback(vim.deepcopy(_cached_models.ids), nil)
		return
	end

	M.get_token(function(token_data, token_err)
		if token_err then
			callback(nil, token_err)
			return
		end

		local endpoint = token_data.endpoint or "https://api.githubcopilot.com/chat/completions"
		request_models(token_data.token, endpoint, function(ids, err)
			if err then
				callback(nil, err)
				return
			end
			_cached_models = { ids = ids, expires_at = os.time() + MODELS_CACHE_TTL }
			callback(vim.deepcopy(ids), nil)
		end)
	end)
end

function M.logout()
	_cached_oauth_token = nil
	_cached_copilot_token = nil
	_cached_models = nil
	_token_refresh_in_progress = false
	_pending_callbacks = {}
end

-- Exposed for testing only
M._testing = {
	find_copilot_config_path = find_copilot_config_path,
	read_copilot_plugin_oauth_token = read_copilot_plugin_oauth_token,
	resolve_oauth_token = resolve_oauth_token,
	is_copilot_token_valid = is_copilot_token_valid,
	get_valid_copilot_token = get_valid_copilot_token,
	set_cached_oauth_token = function(token)
		_cached_oauth_token = token
	end,
	set_cached_copilot_token = function(token_data)
		_cached_copilot_token = token_data
	end,
	get_cached_oauth_token = function()
		return _cached_oauth_token
	end,
	get_cached_copilot_token = function()
		return _cached_copilot_token
	end,
	set_mock_fetch_copilot_token = function(mock_fn)
		_mock_fetch_copilot_token = mock_fn
	end,
	clear_mock_fetch_copilot_token = function()
		_mock_fetch_copilot_token = nil
	end,
	set_mock_fetch_models = function(mock_fn)
		_mock_fetch_models = mock_fn
	end,
	clear_mock_fetch_models = function()
		_mock_fetch_models = nil
	end,
	set_cached_models = function(models)
		_cached_models = models
	end,
	get_cached_models = function()
		return _cached_models
	end,
	parse_models_response = parse_models_response,
	models_url_from_chat_endpoint = models_url_from_chat_endpoint,
}

return M
