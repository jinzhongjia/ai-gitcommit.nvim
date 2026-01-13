# ai-gitcommit.nvim

An AI-powered git commit message generator for Neovim. Generate contextually relevant commit messages using OpenAI, Anthropic, or GitHub Copilot with streaming output.

## Requirements

- Neovim 0.11 or later
- Git
- One of: OpenAI API key, Anthropic API key, or GitHub Copilot authentication

## Installation

### Using lazy.nvim

```lua
{
  "your-username/ai-gitcommit.nvim",
  event = "FileType gitcommit",
  config = function()
    require("ai-gitcommit").setup({
      provider = "openai",
      language = "English",
      commit_style = "conventional",
    })
  end,
}
```

### Using packer.nvim

```lua
use {
  "your-username/ai-gitcommit.nvim",
  ft = "gitcommit",
  config = function()
    require("ai-gitcommit").setup({
      provider = "openai",
      language = "English",
      commit_style = "conventional",
    })
  end,
}
```

## Configuration

### Basic Setup

```lua
require("ai-gitcommit").setup({
  provider = "openai",
  language = "English",
  commit_style = "conventional",
})
```

### Configuration Options

All configuration options with their defaults:

```lua
require("ai-gitcommit").setup({
  -- AI Provider: "openai", "anthropic", or "copilot"
  provider = "openai",

  -- Provider-specific configurations
  providers = {
    openai = {
      -- API key (string, function, or environment variable)
      api_key = vim.env.OPENAI_API_KEY,
      -- Alternatively, use a command to retrieve the API key
      api_key_cmd = nil, -- e.g., { "pass", "show", "openai/api-key" }
      model = "gpt-4o-mini",
      endpoint = "https://api.openai.com/v1/chat/completions",
      max_tokens = 500,
    },

    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
      api_key_cmd = nil,
      model = "claude-3-5-sonnet-20241022",
      endpoint = "https://api.anthropic.com/v1/messages",
      max_tokens = 500,
    },

    copilot = {
      -- Copilot uses OAuth, no API key needed
      model = "gpt-4o",
    },
  },

  -- Output language for commit messages
  language = "English",

  -- Commit style: "conventional" or "simple"
  -- conventional: follows Conventional Commits format
  -- simple: plain language commit messages
  commit_style = "conventional",

  -- Context and diff handling
  context = {
    -- Maximum number of diff lines to include
    max_diff_lines = 500,
    -- Maximum number of characters in diff
    max_diff_chars = 15000,
  },

  -- File filtering for the diff
  filter = {
    -- Patterns to exclude from commit context (Lua regex)
    exclude_patterns = {
      "%.lock$",                 -- lockfiles
      "package%-lock%.json$",   -- npm lockfile
      "yarn%.lock$",             -- yarn lockfile
      "pnpm%-lock%.yaml$",       -- pnpm lockfile
      "%.min%.[jc]ss?$",         -- minified files
      "%.map$",                  -- source maps
    },
    -- Paths to exclude (useful for full directories)
    exclude_paths = {},
    -- If set, only include files matching these patterns
    include_only = nil,
  },

  -- Optional: set a keymap to generate commit message
  keymap = nil, -- e.g., "<leader>vc" to set a keybinding
})
```

### Advanced API Key Configuration

The plugin supports multiple ways to provide API keys:

#### 1. Environment Variable (Recommended)

```lua
require("ai-gitcommit").setup({
  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
    },
  },
})
```

Set environment variables:
```bash
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

#### 2. Function

```lua
require("ai-gitcommit").setup({
  providers = {
    openai = {
      api_key = function()
        return vim.fn.system("security find-generic-password -w -a openai"):gsub("\n", "")
      end,
    },
  },
})
```

#### 3. Command

```lua
require("ai-gitcommit").setup({
  providers = {
    openai = {
      api_key_cmd = { "pass", "show", "openai/api-key" },
    },
  },
})
```

#### 4. Direct String

```lua
require("ai-gitcommit").setup({
  providers = {
    openai = {
      api_key = "sk-...",
    },
  },
})
```

## Usage

### Command

`:AICommit` is the only command you need.

```vim
:AICommit                      " Generate commit message
:AICommit [extra context]      " Generate with additional context
:AICommit login <provider>     " OAuth login (copilot/codex/claude)
:AICommit logout <provider>    " OAuth logout
:AICommit status               " Show OAuth status
```

Examples:

```vim
" Generate a basic commit message
:AICommit

" Generate with additional context
:AICommit This is a hotfix for the login issue

" Login to GitHub Copilot
:AICommit login copilot

" Check authentication status
:AICommit status
```

The generate command only works inside a git commit message buffer (when git opens your editor for a commit).

### Keybinding

To set a keybinding (useful for gitcommit buffer):

```lua
require("ai-gitcommit").setup({
  keymap = "<leader>vc",
})
```

Then use `<leader>vc` to generate a commit message in any gitcommit buffer.

## Provider Setup

### OpenAI

1. Get an API key from https://platform.openai.com/account/api-keys
2. Configure:

```lua
require("ai-gitcommit").setup({
  provider = "openai",
  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      model = "gpt-4o-mini", -- or "gpt-4o" for higher quality
    },
  },
})
```

3. Set environment variable:

```bash
export OPENAI_API_KEY="sk-..."
```

### Anthropic

1. Get an API key from https://console.anthropic.com/account/keys
2. Configure:

```lua
require("ai-gitcommit").setup({
  provider = "anthropic",
  providers = {
    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
      model = "claude-3-5-sonnet-20241022",
    },
  },
})
```

3. Set environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### GitHub Copilot

Copilot authentication is OAuth-based and doesn't require manual API key management.

1. Configure:

```lua
require("ai-gitcommit").setup({
  provider = "copilot",
  providers = {
    copilot = {
      model = "gpt-4o",
    },
  },
})
```

2. Login when ready:

```vim
:AICommit login copilot
```

3. Check status:

```vim
:AICommit status
```

## Commit Styles

### Conventional Commits

Generates messages following the Conventional Commits format (recommended for projects using semantic versioning).

Format: `type(scope): description`

Types: feat, fix, docs, style, refactor, test, chore, perf, ci, build

Example:
```
feat(auth): add OAuth support for GitHub Copilot
fix(streaming): handle empty response chunks correctly
docs: update API documentation
```

```lua
require("ai-gitcommit").setup({
  commit_style = "conventional",
})
```

### Simple

Generates plain language commit messages without strict format constraints.

Example:
```
Add OAuth support for GitHub Copilot
Fix handling of empty response chunks
Update API documentation
```

```lua
require("ai-gitcommit").setup({
  commit_style = "simple",
})
```

## File Filtering

The plugin automatically excludes certain files from the commit context to reduce noise and token usage.

### Default Excluded Patterns

By default, the following file patterns are excluded:
- `*.lock` - Lockfiles (package.lock, etc.)
- `package-lock.json` - npm lockfile
- `yarn.lock` - yarn lockfile
- `pnpm-lock.yaml` - pnpm lockfile
- `*.min.js` / `*.min.css` - Minified files
- `*.map` - Source maps

### Customizing Filters

Override the default patterns:

```lua
require("ai-gitcommit").setup({
  filter = {
    exclude_patterns = {
      "%.lock$",
      "package%-lock%.json$",
      "yarn%.lock$",
      "pnpm%-lock%.yaml$",
      "%.min%.[jc]ss?$",
      "%.map$",
      -- Add your own patterns
      "%.tmp$",           -- ignore .tmp files
      "build/.*",         -- ignore everything in build/
    },
  },
})
```

### Excluding Entire Paths

```lua
require("ai-gitcommit").setup({
  filter = {
    exclude_paths = {
      "node_modules/",
      "dist/",
    },
  },
})
```

### Include Only Specific Files

Focus on specific file patterns:

```lua
require("ai-gitcommit").setup({
  filter = {
    -- Only include changes to .lua and .txt files
    include_only = { "%.lua$", "%.txt$" },
  },
})
```

## Workflow

1. Stage your changes with git:

```bash
git add .
```

2. Start a commit:

```bash
git commit
```

3. In the commit message buffer, run:

```vim
:AICommit
```

Or with a keybinding (if configured):

```
<leader>vc
```

4. The AI will generate a commit message based on your staged changes
5. Edit the message if needed
6. Save and exit to complete the commit

## Output Languages

The plugin supports generating commit messages in any language by setting the `language` option:

```lua
require("ai-gitcommit").setup({
  language = "English",     -- or "French", "Spanish", "German", "Japanese", etc.
})
```

Examples:

```lua
-- French commits
require("ai-gitcommit").setup({ language = "French" })

-- Spanish commits
require("ai-gitcommit").setup({ language = "Español" })

-- Japanese commits
require("ai-gitcommit").setup({ language = "Japanese" })
```

## Performance Considerations

### Token Limits

The plugin limits the diff context to prevent excessive API costs:

- `max_diff_lines`: Maximum number of diff lines (default: 500)
- `max_diff_chars`: Maximum characters in diff (default: 15000)

Adjust based on your usage patterns:

```lua
require("ai-gitcommit").setup({
  context = {
    max_diff_lines = 1000,   -- increase for larger commits
    max_diff_chars = 30000,
  },
})
```

### Streaming

The plugin uses streaming responses to show commit messages in real-time as they're generated. This improves perceived performance and allows cancellation if needed.

## Troubleshooting

### "Not in a gitcommit buffer"

The `:AICommit` command only works when editing a git commit message. Make sure you're in a buffer opened by `git commit`.

### "No API key configured"

Ensure your API key is set via environment variable or configuration. Check:

```lua
require("ai-gitcommit").setup({
  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
    },
  },
})
```

### "Not authenticated"

For Copilot, run:

```vim
:AICommit login copilot
:AICommit status
```

### Streaming not working

The plugin requires:
- A curl-compatible environment
- Proper network connectivity
- Correct API endpoint configuration

Check your provider's API endpoint is correct in the configuration.

## Configuration Examples

### Minimal Setup with OpenAI

```lua
require("ai-gitcommit").setup({
  provider = "openai",
  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
    },
  },
})
```

### Full Custom Setup

```lua
require("ai-gitcommit").setup({
  provider = "openai",

  providers = {
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      model = "gpt-4o",
      max_tokens = 1000,
    },
    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
      model = "claude-3-5-sonnet-20241022",
    },
  },

  language = "English",
  commit_style = "conventional",

  context = {
    max_diff_lines = 750,
    max_diff_chars = 20000,
  },

  filter = {
    exclude_patterns = {
      "%.lock$",
      "%.min%.[jc]ss?$",
      "%.map$",
      "node_modules/.*",
    },
    exclude_paths = {},
  },

  keymap = "<leader>vc",
})
```

## Limitations

- The `:AICommit` command only works in gitcommit buffers
- The plugin requires an active internet connection for API calls
- Token limits apply based on the configured context size
- Some providers may have rate limiting on their APIs

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! Please ensure code follows the project style and includes appropriate tests.
