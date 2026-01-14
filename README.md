# ai-gitcommit.nvim

AI-powered git commit message generator for Neovim using Anthropic Claude.

## Requirements

- Neovim 0.11+
- curl
- Anthropic account (free tier available)

## Installation

```lua
-- lazy.nvim
{
  "your-username/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  opts = {},
}
```

## Setup

1. Install the plugin
2. Run `:AICommit login` to authenticate with Anthropic
3. Stage your changes with `git add`
4. Run `git commit` and use `:AICommit` to generate a message

## Usage

```vim
:AICommit                       " Generate commit message
:AICommit [context]             " Generate with extra context
:AICommit login                 " OAuth login to Anthropic
:AICommit logout                " Logout from Anthropic
:AICommit status                " Show auth status
```

## Configuration

```lua
require("ai-gitcommit").setup({
  model = "claude-haiku-4-5",
  endpoint = "https://api.anthropic.com/v1/messages",
  max_tokens = 500,
  languages = { "English", "Chinese", "Japanese", "Korean" },
  prompt_template = nil, -- custom prompt template (optional)
  keymap = nil, -- e.g. "<leader>gc"
  context = {
    max_diff_lines = 500,
    max_diff_chars = 15000,
  },
  filter = {
    exclude_patterns = { "%.lock$", "package%-lock%.json$" },
    exclude_paths = {},
  },
})
```

### Custom Prompt Template

You can customize the prompt template using placeholders:

```lua
require("ai-gitcommit").setup({
  prompt_template = [[
Generate a commit message for these changes.
Write in {language}. Be concise.

{extra_context}

Files: {staged_files}

Diff:
{diff}

Respond with ONLY the commit message.
]]
})
```

Available placeholders:
- `{language}` - Selected language
- `{extra_context}` - User-provided context
- `{staged_files}` - List of staged files
- `{diff}` - Git diff content

## License

MIT
