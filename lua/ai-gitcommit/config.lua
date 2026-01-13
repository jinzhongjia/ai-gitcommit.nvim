---@class AIGitCommit.ProviderConfig
---@field api_key? string|function
---@field api_key_cmd? string[]
---@field oauth? boolean
---@field model string
---@field endpoint? string
---@field max_tokens? number

---@class AIGitCommit.ContextConfig
---@field max_diff_lines? number
---@field max_diff_chars? number

---@class AIGitCommit.FilterConfig
---@field exclude_patterns? string[]
---@field exclude_paths? string[]
---@field include_only? string[]

---@class AIGitCommit.Config
---@field provider string
---@field providers table<string, AIGitCommit.ProviderConfig>
---@field language string
---@field commit_style string
---@field context AIGitCommit.ContextConfig
---@field filter AIGitCommit.FilterConfig
---@field keymap? string

local M = {}

---@type AIGitCommit.Config
local defaults = {
	provider = "openai",

	providers = {
		openai = {
			api_key = vim.env.OPENAI_API_KEY,
			model = "gpt-4o-mini",
			endpoint = "https://api.openai.com/v1/chat/completions",
			max_tokens = 500,
		},
		anthropic = {
			api_key = vim.env.ANTHROPIC_API_KEY,
			model = "claude-3-5-sonnet-20241022",
			endpoint = "https://api.anthropic.com/v1/messages",
			max_tokens = 500,
		},
		copilot = {
			model = "gpt-4o",
		},
	},

	language = "English",
	commit_style = "conventional",

	context = {
		max_diff_lines = 500,
		max_diff_chars = 15000,
	},

	filter = {
		exclude_patterns = {
			"%.lock$",
			"package%-lock%.json$",
			"yarn%.lock$",
			"pnpm%-lock%.yaml$",
			"%.min%.[jc]ss?$",
			"%.map$",
		},
		exclude_paths = {},
		include_only = nil,
	},

	keymap = nil,
}

---@type AIGitCommit.Config
local config = vim.deepcopy(defaults)

local valid_providers = { "openai", "anthropic", "copilot" }

---@param provider string
---@return boolean
local function is_valid_provider(provider)
	for _, p in ipairs(valid_providers) do
		if p == provider then
			return true
		end
	end
	return false
end

---@param t1 table
---@param t2 table
---@return table
local function deep_merge(t1, t2)
	local result = vim.deepcopy(t1)
	for k, v in pairs(t2) do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = deep_merge(result[k], v)
		else
			result[k] = v
		end
	end
	return result
end

---@param opts? AIGitCommit.Config
function M.setup(opts)
	opts = opts or {}

	if opts.provider and not is_valid_provider(opts.provider) then
		error(
			string.format(
				"Invalid provider '%s'. Valid providers: %s",
				opts.provider,
				table.concat(valid_providers, ", ")
			)
		)
	end

	config = deep_merge(defaults, opts)
end

---@return AIGitCommit.Config
function M.get()
	return config
end

---@return AIGitCommit.ProviderConfig
function M.get_provider()
	local provider_name = config.provider
	local provider_config = config.providers[provider_name]

	if not provider_config then
		error(string.format("Provider '%s' not configured", provider_name))
	end

	return provider_config
end

---@param provider_name? string
---@param callback fun(key: string?, err: string?)
function M.get_api_key(provider_name, callback)
	provider_name = provider_name or config.provider
	local provider_config = config.providers[provider_name]

	if not provider_config then
		callback(nil, string.format("Provider '%s' not configured", provider_name))
		return
	end

	if provider_name == "copilot" then
		callback(nil, "Copilot uses OAuth authentication")
		return
	end

	local api_key = provider_config.api_key

	if type(api_key) == "function" then
		local ok, result = pcall(api_key)
		if ok and result then
			callback(result)
		else
			callback(nil, "API key function failed")
		end
		return
	end

	if type(api_key) == "string" and api_key ~= "" then
		callback(api_key)
		return
	end

	if provider_config.api_key_cmd then
		local uv = vim.uv
		local stdout_pipe = uv.new_pipe()
		local stdout_chunks = {}
		local cmd = provider_config.api_key_cmd[1]
		local args = { unpack(provider_config.api_key_cmd, 2) }

		local handle = uv.spawn(cmd, {
			args = args,
			stdio = { nil, stdout_pipe, nil },
		}, function(code)
			stdout_pipe:close()
			local stdout = table.concat(stdout_chunks, "")
			vim.schedule(function()
				if code == 0 and stdout ~= "" then
					callback(vim.trim(stdout))
				else
					callback(nil, "API key command failed")
				end
			end)
		end)

		if handle then
			stdout_pipe:read_start(function(err, data)
				if data then
					table.insert(stdout_chunks, data)
				end
			end)
		else
			callback(nil, "Failed to run API key command")
		end
		return
	end

	callback(nil, string.format("No API key configured for provider '%s'", provider_name))
end

---@param provider_name? string
---@return boolean
function M.requires_oauth(provider_name)
	provider_name = provider_name or config.provider

	if provider_name == "copilot" then
		return true
	end

	local provider_config = config.providers[provider_name]
	return provider_config and provider_config.oauth == true
end

function M.reset()
	config = vim.deepcopy(defaults)
end

return M
