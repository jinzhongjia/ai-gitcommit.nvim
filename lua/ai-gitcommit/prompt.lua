local M = {}

M.default_template = [[
Generate a git commit message for the following changes.
{commit_type_hint}
Requirements:
- Follow Conventional Commits: type(scope): description
- Types:
  - feat: new feature
  - fix: bug fix
  - docs: documentation only
  - style: formatting, no code change
  - refactor: code change without feature/fix
  - test: adding/updating tests
  - chore: maintenance tasks
  - perf: performance improvement
- Use present tense ("Add" not "Added")
- Subject line must be under 72 characters
- Prefer single-line; omit scope if unclear
- Write in {language}
- Focus on WHY, not just WHAT

{extra_context}

Staged files:
{staged_files}

Diff:
```diff
{diff}
```

IMPORTANT: Output ONLY the commit message. No quotes, markdown, explanations, or extra text.]]

---@class AIGitCommit.PromptOptions
---@field template? string|fun(default_prompt: string): string
---@field language string
---@field extra_context? string
---@field files AIGitCommit.StagedFile[]
---@field diff string
---@field commit_type? AIGitCommit.CommitType
---@field squash_messages? string

---@param commit_type AIGitCommit.CommitType?
---@param squash_messages string?
---@return string
local function build_commit_type_hint(commit_type, squash_messages)
	if commit_type == "amend" then
		return "\nNote: This is an amend commit. Generate a new commit message for the complete amended changes.\n"
	elseif commit_type == "squash" then
		local hint = "\nNote: This is a squash commit combining multiple commits.\n"
		if squash_messages and squash_messages ~= "" then
			hint = hint .. "Original commit messages:\n" .. squash_messages .. "\n"
		end
		return hint
	elseif commit_type == "initial" then
		return "\nNote: This is the initial commit of the repository.\n"
	end
	return ""
end

---@param opts AIGitCommit.PromptOptions
---@return string
function M.build(opts)
	local template
	if type(opts.template) == "function" then
		template = opts.template(M.default_template)
	else
		template = opts.template or M.default_template
	end

	local staged_files_str = ""
	for _, file in ipairs(opts.files or {}) do
		staged_files_str = staged_files_str .. string.format("  %s  %s\n", file.status, file.file)
	end

	local extra = ""
	if opts.extra_context and opts.extra_context ~= "" then
		extra = string.format("Additional context from user: %s\n", opts.extra_context)
	end

	-- Escape % in replacement strings to prevent "invalid capture index" error
	local function escape_replacement(s)
		return (s:gsub("%%", "%%%%"))
	end

	local commit_hint = build_commit_type_hint(opts.commit_type, opts.squash_messages)

	return (template:gsub("{commit_type_hint}", escape_replacement(commit_hint))
		:gsub("{language}", escape_replacement(opts.language or "English"))
		:gsub("{extra_context}", escape_replacement(extra))
		:gsub("{staged_files}", escape_replacement(staged_files_str))
		:gsub("{diff}", escape_replacement(opts.diff or "")))
end

return M
