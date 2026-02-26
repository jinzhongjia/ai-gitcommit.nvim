---@class AIGitCommit.ProviderConfig
---@field api_key? string|fun():string
---@field model string
---@field endpoint string
---@field max_tokens number

---@class AIGitCommit.CopilotProviderConfig: AIGitCommit.ProviderConfig
---@field client_id string

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
---@field providers table<string, AIGitCommit.ProviderConfig|AIGitCommit.CopilotProviderConfig>
---@field languages string[]
---@field prompt_template? string|fun(default_prompt: string): string
---@field context AIGitCommit.ContextConfig
---@field filter AIGitCommit.FilterConfig
---@field keymap? string
---@field auto? AIGitCommit.AutoConfig

local M = {}

local supported_providers = {
	openai = true,
	anthropic = true,
	copilot = true,
}

local default_copilot_client_id = "Iv1.b507a08c87ecfe98"

---@type AIGitCommit.Config
local defaults = {
	provider = nil,
	providers = {
		openai = {
			api_key = nil,
			model = "gpt-4o-mini",
			endpoint = "https://api.openai.com/v1/chat/completions",
			max_tokens = 500,
		},
		anthropic = {
			api_key = nil,
			model = "claude-haiku-4-5",
			endpoint = "https://api.anthropic.com/v1/messages",
			max_tokens = 500,
		},
		copilot = {
			model = "gpt-4o",
			endpoint = "https://api.githubcopilot.com/chat/completions",
			max_tokens = 500,
			client_id = default_copilot_client_id,
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

---@return { name: string, config: AIGitCommit.ProviderConfig|AIGitCommit.CopilotProviderConfig }?, string?
function M.get_provider()
	local provider_name = config.provider
	if not provider_name or provider_name == "" then
		return nil, "No provider configured. Set `provider = \"openai\"|\"anthropic\"|\"copilot\"`"
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
	return true, nil
end

function M.reset()
	config = vim.deepcopy(defaults)
end

return M
