local new_set = MiniTest.new_set

local T = new_set()

local git

T["setup"] = function()
	git = require("ai-gitcommit.git")
end


T["get_staged_diff"] = new_set()

T["get_staged_diff"]["returns error when git command fails"] = function()
	local original_system = vim.system
	local done = false
	local diff = nil
	local err = nil

	vim.system = function(_, _, cb)
		cb({ code = 128, stdout = "", stderr = "fatal: not a git repository" })
		return {
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	git.get_staged_diff(nil, function(result, result_err)
		diff = result
		err = result_err
		done = true
	end)

	vim.wait(500, function()
		return done
	end)

	vim.system = original_system

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(diff, "")
	MiniTest.expect.equality(type(err), "string")
end

T["get_staged_files"] = new_set()

T["get_staged_files"]["parses rename and copy records from -z output"] = function()
	local original_system = vim.system
	local done = false
	local files = nil

	vim.system = function(_, _, cb)
		cb({
			code = 0,
			stdout = table.concat({
				"R100",
				"old-name.lua",
				"new-name.lua",
				"C100",
				"old-copy.lua",
				"new-copy.lua",
				"M",
				"plain.lua",
			}, "\0") .. "\0",
			stderr = "",
		})
		return {
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	git.get_staged_files(nil, function(result)
		files = result
		done = true
	end)

	vim.wait(500, function()
		return done
	end)

	vim.system = original_system

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(files[1].status, "R100")
	MiniTest.expect.equality(files[1].file, "old-name.lua -> new-name.lua")
	MiniTest.expect.equality(files[1].old_file, "old-name.lua")
	MiniTest.expect.equality(files[1].new_file, "new-name.lua")
	MiniTest.expect.equality(files[2].status, "C100")
	MiniTest.expect.equality(files[2].old_file, "old-copy.lua")
	MiniTest.expect.equality(files[2].new_file, "new-copy.lua")
	MiniTest.expect.equality(files[3].status, "M")
	MiniTest.expect.equality(files[3].file, "plain.lua")
end

T["get_staged_files"]["returns error when git command fails"] = function()
	local original_system = vim.system
	local done = false
	local files = nil
	local err = nil

	vim.system = function(_, _, cb)
		cb({ code = 128, stdout = "", stderr = "fatal: not a git repository" })
		return {
			is_closing = function()
				return false
			end,
			kill = function(_, _) end,
		}
	end

	git.get_staged_files(nil, function(result, result_err)
		files = result
		err = result_err
		done = true
	end)

	vim.wait(500, function()
		return done
	end)

	vim.system = original_system

	MiniTest.expect.equality(done, true)
	MiniTest.expect.equality(type(files), "table")
	MiniTest.expect.equality(#files, 0)
	MiniTest.expect.equality(type(err), "string")
end

---@type string?
local repo
---@type integer?
local repo_buf

---@param args string[]
---@return string
local function repo_git(args)
	local cmd = { "git", "-C", repo }
	vim.list_extend(cmd, args)
	local result = vim.system(cmd):wait()
	assert(result.code == 0, result.stderr)
	return result.stdout or ""
end

T["configured_repository"] = new_set({
	hooks = {
		pre_case = function()
			repo = vim.fn.tempname()
			vim.fn.mkdir(repo, "p")
			repo_git({ "init", "-q" })
			vim.fn.writefile({ "content" }, vim.fs.joinpath(repo, "file.lua"))
			repo_git({ "add", "file.lua" })
			repo_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(repo_buf, vim.fs.joinpath(repo, "file.lua"))
		end,
		post_case = function()
			if repo_buf and vim.api.nvim_buf_is_valid(repo_buf) then
				vim.api.nvim_buf_delete(repo_buf, { force = true })
			end
			if repo then
				vim.fn.delete(repo, "rf")
			end
			repo, repo_buf = nil, nil
		end,
	},
})

T["configured_repository"]["returns filterable patches regardless of display configuration"] = function()
	repo_git({ "config", "color.ui", "always" })
	repo_git({ "config", "diff.noprefix", "true" })
	repo_git({ "config", "diff.external", "ai-gitcommit-nonexistent-diff-command" })
	repo_git({
		"-c",
		"user.name=Test",
		"-c",
		"user.email=test@example.com",
		"-c",
		"commit.gpgsign=false",
		"commit",
		"--no-verify",
		"-qm",
		"fixture",
	})
	vim.fn.writefile({ "changed" }, vim.fs.joinpath(repo, "file.lua"))
	repo_git({ "add", "file.lua" })

	for _, get_diff in ipairs({ git.get_staged_diff, git.get_head_diff }) do
		local done, diff, err = false, nil, nil
		get_diff(repo_buf, function(result, result_err)
			diff, err, done = result, result_err, true
		end)
		MiniTest.expect.equality(vim.wait(3000, function()
			return done
		end), true)
		MiniTest.expect.equality(err, nil)
		MiniTest.expect.equality(diff:find("diff --git a/file.lua b/file.lua", 1, true), 1)
		MiniTest.expect.equality(diff:find("\27", 1, true), nil)
		MiniTest.expect.equality(
			require("ai-gitcommit.context").filter_diff(diff, { filter = { exclude_patterns = { "^file%.lua$" } } }),
			""
		)
	end
end

return T
