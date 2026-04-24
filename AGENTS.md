# AI Agents Development Guide

## After Every Code Change

```bash
mise run lint   # 0 warnings / 0 errors
mise run test   # All tests must pass
```

## Technical Constraints

### Must Follow

- **Neovim version**: 0.11+ only, no backward compatibility needed
- **Test framework**: mini.test, not plenary
- **Type annotations**: Keep LuaLS annotations (`---@param`, `---@class`, etc.)
- **Providers**: Only openai / copilot
- **Docs**: update doc/ai-gitcommit.txt and readme after code changes
- **Compatibility**: Must work on Linux, macOS, Windows

### Forbidden

- Depending on plenary.nvim
- Expanding the provider list beyond `openai` and `copilot`
  (use OpenAI-compatible endpoints for Ollama / vLLM / local inference instead)
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
:AICommit logout <provider>
:AICommit status
```

## File Structure

```
lua/ai-gitcommit/
├── init.lua          # Entry wiring (setup/generate)
├── commands.lua      # :AICommit command + completion
├── generator.lua     # Generate pipeline
├── autogen.lua       # FileType gitcommit autocmd + debounce
├── buffer_state.lua  # Per-buffer state
├── config.lua        # Configuration
├── git.lua           # Git operations
├── stream.lua        # HTTP streaming (SSE)
├── buffer.lua        # Buffer operations
├── context.lua       # Diff filtering/truncation
├── prompt.lua        # Prompt templates
├── typewriter.lua    # Streaming text display
├── auth/             # OAuth (copilot only)
├── providers/        # openai / copilot (+ shared openai_compat)
└── util/             # Shared curl / fs helpers
```

## Testing

- Test files in `tests/test_*.lua`
- Use `MiniTest.expect.equality()` for assertions
- Run single test: `mise run test-file tests/test_config.lua`
