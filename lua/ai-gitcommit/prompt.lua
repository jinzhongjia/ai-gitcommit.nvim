local M = {}

M.default_template = [[
Generate a git commit message for the following changes.

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

	return (template:gsub("{language}", opts.language or "English")
		:gsub("{extra_context}", extra)
		:gsub("{staged_files}", staged_files_str)
		:gsub("{diff}", opts.diff or ""))
end

return M
