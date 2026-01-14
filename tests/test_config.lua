local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

T["setup"] = new_set()

T["setup"]["applies default config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup()

	local cfg = config.get()
	MiniTest.expect.equality(cfg.model, "claude-haiku-4-5")
	MiniTest.expect.equality(cfg.languages[1], "English")
	MiniTest.expect.equality(cfg.commit_style, "conventional")
end

T["setup"]["merges user config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({
		model = "claude-sonnet-4-20250514",
		languages = { "Chinese", "English" },
	})

	local cfg = config.get()
	MiniTest.expect.equality(cfg.model, "claude-sonnet-4-20250514")
	MiniTest.expect.equality(cfg.languages[1], "Chinese")
	MiniTest.expect.equality(cfg.languages[2], "English")
	MiniTest.expect.equality(cfg.commit_style, "conventional")
end

T["get_provider"] = new_set()

T["get_provider"]["returns provider config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup()

	local provider = config.get_provider()
	MiniTest.expect.equality(provider.model, "claude-haiku-4-5")
	MiniTest.expect.equality(provider.endpoint, "https://api.anthropic.com/v1/messages")
	MiniTest.expect.equality(provider.max_tokens, 500)
end

T["reset"] = new_set()

T["reset"]["restores defaults"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({ languages = { "Chinese" } })
	config.reset()

	local cfg = config.get()
	MiniTest.expect.equality(cfg.languages[1], "English")
end

return T
