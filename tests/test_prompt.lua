local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

local prompt

T["setup"] = function()
	prompt = require("ai-gitcommit.prompt")
end

T["build"] = new_set()

T["build"]["generates default commit prompt"] = function()
	local result = prompt.build({
		language = "English",
		diff = helpers.get_sample_diff(),
		files = { { status = "M", file = "src/main.lua" } },
	})

	MiniTest.expect.equality(result:find("Conventional Commits") ~= nil, true)
	MiniTest.expect.equality(result:find("src/main.lua") ~= nil, true)
end

T["build"]["uses custom string template when provided"] = function()
	local result = prompt.build({
		template = "Custom: {language} {diff}",
		language = "English",
		diff = "test diff",
		files = {},
	})

	MiniTest.expect.equality(result:find("Custom:") ~= nil, true)
	MiniTest.expect.equality(result:find("test diff") ~= nil, true)
end

T["build"]["uses custom function template when provided"] = function()
	local result = prompt.build({
		template = function(default)
			return default .. "\n\nALWAYS_USE_EMOJI"
		end,
		language = "English",
		diff = "test diff",
		files = {},
	})

	MiniTest.expect.equality(result:find("Conventional Commits") ~= nil, true)
	MiniTest.expect.equality(result:find("ALWAYS_USE_EMOJI") ~= nil, true)
end

T["build"]["includes language"] = function()
	local result = prompt.build({
		language = "Chinese",
		diff = "test",
		files = {},
	})

	MiniTest.expect.equality(result:find("Chinese") ~= nil, true)
end

T["build"]["includes extra context when provided"] = function()
	local result = prompt.build({
		language = "English",
		extra_context = "This fixes the login bug",
		diff = "test",
		files = {},
	})

	MiniTest.expect.equality(result:find("fixes the login bug") ~= nil, true)
end

T["build"]["handles missing extra context"] = function()
	local result = prompt.build({
		language = "English",
		diff = "test",
		files = {},
	})

	MiniTest.expect.equality(result:find("Additional context") == nil, true)
end

T["build"]["preserves literal placeholders and percent signs in replacement values"] = function()
	local result = prompt.build({
		template = "{language}|{extra_context}|{staged_files}|{diff}|{unknown}",
		language = "English",
		extra_context = "Explain {diff} and {staged_files} at 100%",
		files = { { status = "M", file = "{diff}%1.lua" } },
		diff = "+{language} = '%1'",
	})

	MiniTest.expect.equality(
		result,
		"English|Additional context from user: Explain {diff} and {staged_files} at 100%\n"
			.. "|  M  {diff}%1.lua\n|+{language} = '%1'|{unknown}"
	)
end

T["default_template"] = new_set()

T["default_template"]["exists"] = function()
	MiniTest.expect.equality(prompt.default_template ~= nil, true)
end

return T
