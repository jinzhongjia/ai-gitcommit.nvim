---@class AIGitCommit.ProviderConfig
---@field api_key? string|fun():string
---@field api_key_required? boolean
---@field api_key_header? string
---@field api_key_prefix? string
---@field extra_headers? table<string, string>
---@field stream_options? boolean
---@field model? string
---@field endpoint string
---@field max_tokens number

---@class AIGitCommit.Credentials
---@field api_key? string
---@field endpoint? string
---@field model? string

---@class AIGitCommit.ContextConfig
---@field max_diff_lines? number
---@field max_diff_chars? number

---@class AIGitCommit.FilterConfig
---@field exclude_patterns? string[]
---@field exclude_paths? string[]
---@field include_only? string[]

---@class AIGitCommit.AutoConfig
---@field enabled boolean
---@field debounce_ms? number

---@class AIGitCommit.Config
---@field provider? string
---@field providers table<string, AIGitCommit.ProviderConfig>
---@field languages string[]
---@field prompt_template? string|fun(default_prompt: string): string
---@field context AIGitCommit.ContextConfig
---@field filter AIGitCommit.FilterConfig
---@field keymap? string
---@field auto? AIGitCommit.AutoConfig

local M = {}

local supported_providers = {
	openai = true,
	copilot = true,
}

---@type AIGitCommit.Config
local defaults = {
	provider = "copilot",
	providers = {
		openai = {
			api_key = nil,
			api_key_required = true,
			api_key_header = "Authorization",
			api_key_prefix = "Bearer ",
			extra_headers = {},
			stream_options = true,
			model = "gpt-4o-mini",
			endpoint = "https://api.openai.com/v1/chat/completions",
			max_tokens = 500,
		},
		copilot = {
			-- model is resolved dynamically from Copilot's /models endpoint;
			-- set explicitly here to pin a specific model.
			model = nil,
			endpoint = "https://api.githubcopilot.com/chat/completions",
			max_tokens = 500,
		},
	},

	languages = { "English", "Chinese", "Japanese", "Korean" },
	prompt_template = nil,

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
			-- Proto generated files
			"%.pb%.go$",
			"_grpc%.pb%.go$",
			"%.pb%.cc$",
			"%.pb%.h$",
			"_pb2%.py$",
			"_pb2_grpc%.py$",
			-- GORM gen generated files
			"%.gen%.go$",
			-- Connect RPC generated files
			"%.connect%.go$",
			"_connect%.ts$",
		},
		exclude_paths = {},
		include_only = nil,
	},

	keymap = nil,

	auto = {
		enabled = true,
		debounce_ms = 450,
	},
}

---@type AIGitCommit.Config
local config = vim.deepcopy(defaults)

---@param t table
---@return boolean
local function is_array(t)
	return type(t) == "table" and vim.islist(t)
end

---@param t1 table
---@param t2 table
---@return table
local function deep_merge(t1, t2)
	local result = vim.deepcopy(t1)
	for k, v in pairs(t2) do
		if type(v) == "table" and type(result[k]) == "table" and not is_array(v) then
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
	config = deep_merge(defaults, opts)
end

---@return AIGitCommit.Config
function M.get()
	return config
end

---@return { name: string, config: AIGitCommit.ProviderConfig }?, string?
function M.get_provider()
	local provider_name = config.provider
	if not provider_name or provider_name == "" then
		return nil, "No provider configured. Set `provider = \"openai\"|\"copilot\"`"
	end

	if not supported_providers[provider_name] then
		return nil, "Unsupported provider: " .. provider_name
	end

	local provider_config = config.providers and config.providers[provider_name]
	if not provider_config then
		return nil, "Missing provider config for: " .. provider_name
	end

	return { name = provider_name, config = provider_config }, nil
end

---@param provider string
---@return boolean
function M.is_supported_provider(provider)
	return supported_providers[provider] == true
end

---@return boolean, string?
function M.validate_provider()
	local provider, err = M.get_provider()
	if not provider then
		return false, err
	end

	-- Copilot resolves model at runtime from /models; allow empty here.
	if provider.name ~= "copilot" then
		if type(provider.config.model) ~= "string" or provider.config.model == "" then
			return false, "Invalid provider model for: " .. provider.name
		end
	end

	if type(provider.config.endpoint) ~= "string" or provider.config.endpoint == "" then
		return false, "Invalid provider endpoint for: " .. provider.name
	end

	local max_tokens = provider.config.max_tokens
	if type(max_tokens) ~= "number" or max_tokens <= 0 then
		return false, "Invalid provider max_tokens for: " .. provider.name
	end

	return true, nil
end

function M.reset()
	config = vim.deepcopy(defaults)
end

return M
