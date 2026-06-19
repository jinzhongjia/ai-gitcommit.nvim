# ai-gitcommit.nvim

AI-powered git commit message generator for Neovim.

Supported providers:
- OpenAI (and compatible endpoints)
- GitHub Copilot

## Requirements

- Neovim 0.11+
- curl
- OpenAI API key, or [copilot.vim](https://github.com/github/copilot.vim) / [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

## Installation

```lua
-- lazy.nvim (Copilot — default, no config needed if copilot.vim/copilot.lua is installed)
{
  "jinzhongjia/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  opts = {},
}

-- lazy.nvim (OpenAI)
{
  "jinzhongjia/ai-gitcommit.nvim",
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
:AICommit logout <provider>     " Clear auth state
:AICommit status                " Show provider status
:AICommit status <provider>     " Show one provider status
```

## Configuration

```lua
require("ai-gitcommit").setup({
  provider = "copilot", -- default
  -- Full option reference: :h ai-gitcommit-config
})
```

OpenAI:

```lua
require("ai-gitcommit").setup({
  provider = "openai",
  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      model = "gpt-4o-mini",
      endpoint = "https://api.openai.com/v1/chat/completions",
    },
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

### Model selection

By default the plugin auto-detects which chat models your Copilot subscription
allows (via Copilot's `/models` endpoint) and **picks the one with the lowest
`billing.multiplier`** — i.e. the cheapest model you can use. Common result:
`grok-code-fast-1` or `gpt-4o-mini` (both `0x` on most plans).

Resolved model list is cached in memory for 30 minutes.

To pin a specific model, set it explicitly:

```lua
providers = {
  copilot = {
    model = "claude-sonnet-4",
  },
},
```

Typical available models (depends on your plan: Free / Pro / Pro+ / Business / Enterprise):
`grok-code-fast-1`, `gpt-4.1`, `gpt-4o`, `gpt-4o-mini`, `claude-sonnet-4`,
`o3-mini`, `o4-mini`, …

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

## Custom Prompt Template

Placeholders: `{language}`, `{extra_context}`, `{staged_files}`, `{diff}`

`prompt_template` may be a string, or a function that receives the default
prompt and returns a replacement string.

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

- `filter.exclude_patterns` — remove files by Lua path pattern
- `filter.include_only` — when non-empty, keep only matching files
- The same filters apply to both diff context and the `Staged files` list in the prompt
- Context is truncated by `context.max_diff_chars`
- Default excludes cover common lockfiles, sourcemaps/minified assets, and generated protobuf / GORM gen / Connect RPC outputs

## Generation behavior

- `:AICommit` works only in a `gitcommit` buffer
- Generation uses staged changes by default
- In `git commit --amend` buffers with an existing message and no staged changes, generation falls back to the current `HEAD` commit diff
- When multiple `languages` are configured, a language picker is shown
- When `auto.enabled = true`, generation starts automatically on `FileType gitcommit` after `debounce_ms`, but only if provider credentials are already available and the commit message area is still untouched

## License

MIT
