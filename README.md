# ai-gitcommit.nvim

AI-powered git commit message generator for Neovim.

Supported providers:
- OpenAI
- Anthropic
- GitHub Copilot (OAuth)

## Requirements

- Neovim 0.11+
- curl

## Installation

```lua
-- lazy.nvim
{
  "your-username/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  opts = {
    provider = "openai",
    providers = {
      openai = {
        api_key = vim.env.OPENAI_API_KEY,
      },
    },
  },
}
```

## Important Migration Note

Old flat config is no longer supported. You must configure:
- `provider`
- `providers.<name>`

If `provider` is not set, `:AICommit` fails with a configuration error.

## Usage

```vim
:AICommit                       " Generate commit message
:AICommit [context]             " Generate with extra context
:AICommit login <provider>      " OAuth login (anthropic/copilot)
:AICommit logout <provider>     " OAuth logout
:AICommit status                " Show provider status
:AICommit status <provider>     " Show one provider status
```

Examples:

```vim
:AICommit login copilot
:AICommit login anthropic
:AICommit status
```

## Configuration

```lua
require("ai-gitcommit").setup({
  provider = "openai", -- required: "openai" | "anthropic" | "copilot"

  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      model = "gpt-4o-mini",
      endpoint = "https://api.openai.com/v1/chat/completions",
      max_tokens = 500,
    },

    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
      model = "claude-haiku-4-5",
      endpoint = "https://api.anthropic.com/v1/messages",
      max_tokens = 500,
    },

    copilot = {
      model = "gpt-4o",
      endpoint = "https://api.githubcopilot.com/chat/completions",
      max_tokens = 500,
      client_id = nil, -- optional override, built-in default is used if nil
    },
  },

  languages = { "English", "Chinese", "Japanese", "Korean" },
  prompt_template = nil,
  keymap = nil,
  context = {
    max_diff_lines = 500,
    max_diff_chars = 15000,
  },
  filter = {
    exclude_patterns = { "%.lock$", "package%-lock%.json$" },
    exclude_paths = {},
    include_only = nil,
  },
  auto = {
    enabled = true,
    debounce_ms = 450,
  },
})
```

## Copilot OAuth

For Copilot, authenticate once:

```vim
:AICommit login copilot
```

The plugin stores OAuth data under your Neovim data dir:
- Linux/macOS: `stdpath("data")/ai-gitcommit/copilot.json`
- Windows: equivalent `stdpath("data")` location

## Custom Prompt Template

Placeholders:
- `{language}`
- `{extra_context}`
- `{staged_files}`
- `{diff}`

## License

MIT
