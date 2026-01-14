---@class AIGitCommit.ProviderConfig
---@field model string
---@field endpoint string
---@field max_tokens number

---@class AIGitCommit.ContextConfig
---@field max_diff_lines? number
---@field max_diff_chars? number

---@class AIGitCommit.FilterConfig
---@field exclude_patterns? string[]
---@field exclude_paths? string[]
---@field include_only? string[]

---@class AIGitCommit.Config
---@field model string
---@field endpoint string
---@field max_tokens number
---@field languages string[]
---@field commit_style string
---@field context AIGitCommit.ContextConfig
---@field filter AIGitCommit.FilterConfig
---@field keymap? string

local M = {}

---@type AIGitCommit.Config
local defaults = {
	model = "claude-haiku-4-5",
	endpoint = "https://api.anthropic.com/v1/messages",
	max_tokens = 500,

	languages = { "English", "Chinese", "Japanese", "Korean" },
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
	config = deep_merge(defaults, opts)
end

---@return AIGitCommit.Config
function M.get()
	return config
end

---@return AIGitCommit.ProviderConfig
function M.get_provider()
	return {
		model = config.model,
		endpoint = config.endpoint,
		max_tokens = config.max_tokens,
	}
end

function M.reset()
	config = vim.deepcopy(defaults)
end

return M
