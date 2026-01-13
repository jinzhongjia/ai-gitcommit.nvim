# AI Agents Development Guide

## After Every Code Change

```bash
make lint   # 0 warnings / 0 errors
make test   # All tests must pass
```

## Technical Constraints

### Must Follow

- **Neovim version**: 0.11+ only, no backward compatibility needed
- **Process operations**: Use `vim.uv` (luv), not `vim.system` / `vim.fn.jobstart`
- **Test framework**: mini.test, not plenary
- **Type annotations**: Keep LuaLS annotations (`---@param`, `---@class`, etc.)
- **Providers**: Only openai / anthropic / copilot

### Forbidden

- Depending on plenary.nvim
- Adding new providers (e.g., Ollama, Gemini)
- Removing type annotations

## Code Style

### Lua

- Tab indentation
- Use `_` for unused variables
- Add type annotations to function parameters

### Commands

Single command `:AICommit` with subcommands:

```
:AICommit [context]
:AICommit login <provider>
:AICommit logout <provider>
:AICommit status
```

## File Structure

```
lua/ai-gitcommit/
├── init.lua          # Entry + commands
├── config.lua        # Configuration
├── git.lua           # Git operations (vim.uv)
├── stream.lua        # HTTP streaming (vim.uv)
├── buffer.lua        # Buffer operations
├── context.lua       # Diff filtering/truncation
├── prompt.lua        # Prompt templates
├── auth/             # OAuth authentication
└── providers/        # LLM providers
```

## Testing

- Test files in `tests/test_*.lua`
- Use `MiniTest.expect.equality()` for assertions
- Run single test: `make test-file FILE=tests/test_config.lua`
