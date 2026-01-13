local helpers = require("tests.helpers")
local new_set = MiniTest.new_set

local T = new_set()

local prompt

T["setup"] = function()
	prompt = require("ai-gitcommit.prompt")
end

T["build"] = new_set()

T["build"]["generates conventional commit prompt"] = function()
	local result = prompt.build({
		style = "conventional",
		language = "English",
		diff = helpers.get_sample_diff(),
		files = { { status = "M", file = "src/main.lua" } },
	})

	MiniTest.expect.equality(result:find("Conventional Commits") ~= nil, true)
	MiniTest.expect.equality(result:find("src/main.lua") ~= nil, true)
end

T["build"]["generates simple prompt"] = function()
	local result = prompt.build({
		style = "simple",
		language = "English",
		diff = "test diff",
		files = {},
	})

	MiniTest.expect.equality(result:find("simple git commit message") ~= nil, true)
end

T["build"]["includes language"] = function()
	local result = prompt.build({
		style = "conventional",
		language = "Chinese",
		diff = "test",
		files = {},
	})

	MiniTest.expect.equality(result:find("Chinese") ~= nil, true)
end

T["build"]["includes extra context when provided"] = function()
	local result = prompt.build({
		style = "conventional",
		language = "English",
		extra_context = "This fixes the login bug",
		diff = "test",
		files = {},
	})

	MiniTest.expect.equality(result:find("fixes the login bug") ~= nil, true)
end

T["build"]["handles missing extra context"] = function()
	local result = prompt.build({
		style = "conventional",
		language = "English",
		diff = "test",
		files = {},
	})

	MiniTest.expect.equality(result:find("Additional context") == nil, true)
end

T["build"]["falls back to conventional for unknown style"] = function()
	local result = prompt.build({
		style = "unknown",
		language = "English",
		diff = "test",
		files = {},
	})

	MiniTest.expect.equality(result:find("Conventional Commits") ~= nil, true)
end

T["templates"] = new_set()

T["templates"]["has conventional template"] = function()
	MiniTest.expect.equality(prompt.templates.conventional ~= nil, true)
end

T["templates"]["has simple template"] = function()
	MiniTest.expect.equality(prompt.templates.simple ~= nil, true)
end

return T
