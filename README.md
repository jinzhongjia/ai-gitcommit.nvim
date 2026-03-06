# ai-gitcommit.nvim

AI-powered git commit message generator for Neovim.

Supported providers:
- OpenAI (and compatible endpoints)
- Anthropic
- GitHub Copilot

## Requirements

- Neovim 0.11+
- curl
- API key (OpenAI/Anthropic) or [copilot.vim](https://github.com/github/copilot.vim) / [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

## Installation

```lua
-- lazy.nvim (Copilot)
{
  "your-username/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  opts = {
    provider = "copilot",
  },
}

-- lazy.nvim (OpenAI)
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

## Usage

```vim
:AICommit                       " Generate commit message
:AICommit [context]             " Generate with extra context
:AICommit login <provider>      " OAuth login (anthropic only)
:AICommit logout <provider>     " Clear auth state
:AICommit status                " Show provider status
:AICommit status <provider>     " Show one provider status
```

## Configuration

```lua
require("ai-gitcommit").setup({
  provider = "copilot", -- required: "openai" | "anthropic" | "copilot"

  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      api_key_required = true,
      api_key_header = "Authorization",
      api_key_prefix = "Bearer ",
      extra_headers = {},
      stream_options = true,
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
      model = "grok-code-fast-1",
      endpoint = "https://api.githubcopilot.com/chat/completions",
      max_tokens = 500,
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

## Copilot

Copilot provider reads OAuth tokens directly from an installed Copilot plugin — **no separate login required**.

### Prerequisites

Install and authenticate one of:
- [copilot.vim](https://github.com/github/copilot.vim) — `:Copilot auth`
- [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

Once authenticated there, `ai-gitcommit.nvim` will automatically detect the token.

### Available models

The model depends on your Copilot subscription (Free/Pro/Pro+/Business/Enterprise):

| Model | ID | Notes |
|---|---|---|
| Grok Code Fast 1 | `grok-code-fast-1` | Default, fast and economical |
| GPT-4.1 | `gpt-4.1` | Copilot's own default |
| GPT-4o | `gpt-4o` | |
| Claude Sonnet 4 | `claude-sonnet-4` | |
| o3-mini | `o3-mini` | Reasoning model |
| o4-mini | `o4-mini` | Reasoning model |

Override via config:

```lua
providers = {
  copilot = {
    model = "claude-sonnet-4",
  },
},
```

## OpenAI-compatible endpoints

Reuse the `openai` provider with a custom endpoint:

```lua
providers = {
  openai = {
    endpoint = "http://localhost:11434/v1/chat/completions",
    api_key_required = false, -- no auth for local services
    model = "llama3",
  },
},
```

- Non-Bearer auth: set `api_key_header` and `api_key_prefix`
- Vendor-specific headers: use `extra_headers`
- If endpoint rejects OpenAI `stream_options`: set `stream_options = false`

## Anthropic

```lua
{
  provider = "anthropic",
  providers = {
    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
    },
  },
}
```

Or use OAuth login:

```vim
:AICommit login anthropic
```

## Custom Prompt Template

Placeholders: `{language}`, `{extra_context}`, `{staged_files}`, `{diff}`

```lua
prompt_template = [[
Generate a commit message for the following changes.
Use {language}, be concise.

{extra_context}

Files: {staged_files}

Diff:
{diff}

Output only the commit message, no explanation.
]]
```

## Diff context behavior

- `filter.exclude_patterns` — remove files by filename pattern
- `filter.exclude_paths` — remove files by path pattern
- `filter.include_only` — when non-empty, keep only matching files
- Context is truncated by `context.max_diff_lines`, then `context.max_diff_chars`

## License

MIT
