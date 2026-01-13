local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

T["setup"] = new_set()

T["setup"]["applies default config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup()

	local cfg = config.get()
	MiniTest.expect.equality(cfg.provider, "openai")
	MiniTest.expect.equality(cfg.language, "English")
	MiniTest.expect.equality(cfg.commit_style, "conventional")
end

T["setup"]["merges user config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({
		provider = "anthropic",
		language = "Chinese",
	})

	local cfg = config.get()
	MiniTest.expect.equality(cfg.provider, "anthropic")
	MiniTest.expect.equality(cfg.language, "Chinese")
	MiniTest.expect.equality(cfg.commit_style, "conventional")
end

T["setup"]["errors on invalid provider"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")

	MiniTest.expect.error(function()
		config.setup({ provider = "invalid" })
	end, "Invalid provider")
end

T["get_provider"] = new_set()

T["get_provider"]["returns provider config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({ provider = "openai" })

	local provider = config.get_provider()
	MiniTest.expect.equality(provider.model, "gpt-4o-mini")
end

T["requires_oauth"] = new_set()

T["requires_oauth"]["returns true for copilot"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup()

	MiniTest.expect.equality(config.requires_oauth("copilot"), true)
end

T["requires_oauth"]["returns false for openai"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup()

	MiniTest.expect.equality(config.requires_oauth("openai"), false)
end

T["reset"] = new_set()

T["reset"]["restores defaults"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({ language = "Chinese" })
	config.reset()

	local cfg = config.get()
	MiniTest.expect.equality(cfg.language, "English")
end

return T
