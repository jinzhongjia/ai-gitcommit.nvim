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
  provider = "copilot", -- "openai" | "copilot" (default: "copilot")

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

    copilot = {
      -- model = nil → auto-select cheapest available via /models
      -- set a string to pin, e.g. "gpt-4o" or "claude-sonnet-4"
      model = nil,
      endpoint = "https://api.githubcopilot.com/chat/completions",
      max_tokens = 500,
    },
  },

  languages = { "English", "Chinese", "Japanese", "Korean" },
  prompt_template = nil, -- string or function(default_prompt) -> string
  keymap = nil,
  context = {
    max_diff_lines = 500,
    max_diff_chars = 15000,
  },
  filter = {
    exclude_patterns = {
      "%.lock$",
      "package%-lock%.json$",
      "yarn%.lock$",
      "pnpm%-lock%.yaml$",
      "%.min%.[jc]ss?$",
      "%.map$",
      "%.pb%.go$",
      "_grpc%.pb%.go$",
      "%.pb%.cc$",
      "%.pb%.h$",
      "_pb2%.py$",
      "_pb2_grpc%.py$",
      "%.gen%.go$",
      "%.connect%.go$",
      "_connect%.ts$",
    },
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

- `filter.exclude_patterns` — remove files by filename pattern
- `filter.exclude_paths` — remove files by path pattern
- `filter.include_only` — when non-empty, keep only matching files
- The same filters apply to both diff context and the `Staged files` list in the prompt
- Context is truncated by `context.max_diff_lines`, then `context.max_diff_chars`
- Default excludes cover common lockfiles, sourcemaps/minified assets, and generated protobuf / GORM gen / Connect RPC outputs

## Generation behavior

- `:AICommit` works only in a `gitcommit` buffer
- Generation uses staged changes by default
- In `git commit --amend` buffers with an existing message and no staged changes, generation falls back to the current `HEAD` commit diff
- When multiple `languages` are configured, a language picker is shown
- When `auto.enabled = true`, generation starts automatically on `FileType gitcommit` after `debounce_ms`, but only if provider credentials are already available and the commit message area is still untouched

## License

MIT
