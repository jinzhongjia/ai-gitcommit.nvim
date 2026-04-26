local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

T["setup"] = new_set()

T["setup"]["applies default config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup()

	local cfg = config.get()
	MiniTest.expect.equality(cfg.provider, "copilot")
	MiniTest.expect.equality(cfg.providers.openai.model, "gpt-4o-mini")
	MiniTest.expect.equality(cfg.providers.copilot.model, nil)
	MiniTest.expect.equality(cfg.languages[1], "English")
end

T["setup"]["merges user config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({
		provider = "openai",
		providers = {
			openai = {
				model = "gpt-4.1-mini",
			},
		},
		languages = { "Chinese", "English" },
	})

	local cfg = config.get()
	MiniTest.expect.equality(cfg.provider, "openai")
	MiniTest.expect.equality(cfg.providers.openai.model, "gpt-4.1-mini")
	MiniTest.expect.equality(cfg.languages[1], "Chinese")
	MiniTest.expect.equality(cfg.languages[2], "English")
end

T["get_provider"] = new_set()

T["get_provider"]["returns selected provider config"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({ provider = "copilot" })

	local provider, err = config.get_provider()
	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(provider.name, "copilot")
	MiniTest.expect.equality(provider.config.endpoint, "https://api.githubcopilot.com/chat/completions")
end

T["get_provider"]["returns copilot by default"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup()

	local provider, err = config.get_provider()
	MiniTest.expect.equality(err, nil)
	MiniTest.expect.equality(provider.name, "copilot")
end

T["get_provider"]["returns error when provider is empty string"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({ provider = "" })

	local provider, err = config.get_provider()
	MiniTest.expect.equality(provider, nil)
	MiniTest.expect.equality(type(err), "string")
end

T["validate_provider"] = new_set()

T["validate_provider"]["fails on unsupported provider"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({ provider = "invalid" })

	local ok, err = config.validate_provider()
	MiniTest.expect.equality(ok, false)
	MiniTest.expect.equality(type(err), "string")
end

T["validate_provider"]["fails on empty model"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({
		provider = "openai",
		providers = {
			openai = {
				model = "",
			},
		},
	})

	local ok, err = config.validate_provider()
	MiniTest.expect.equality(ok, false)
	MiniTest.expect.equality(type(err), "string")
end

T["validate_provider"]["fails on invalid max_tokens"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({
		provider = "copilot",
		providers = {
			copilot = {
				max_tokens = 0,
			},
		},
	})

	local ok, err = config.validate_provider()
	MiniTest.expect.equality(ok, false)
	MiniTest.expect.equality(type(err), "string")
end

T["reset"] = new_set()

T["reset"]["restores defaults"] = function()
	helpers.reset_config()
	local config = require("ai-gitcommit.config")
	config.setup({ provider = "openai", languages = { "Chinese" } })
	config.reset()

	local cfg = config.get()
	MiniTest.expect.equality(cfg.provider, "copilot")
	MiniTest.expect.equality(cfg.languages[1], "English")
end

return T
