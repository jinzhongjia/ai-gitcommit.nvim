# AI Agents Development Guide

## After Every Code Change

```bash
mise run lint   # 0 warnings / 0 errors
mise run test   # All tests must pass
```

Single-test file: `mise run test-file tests/test_config.lua`.

## Technical Constraints

### Must Follow

- **Neovim version**: 0.11+ only, no backward compatibility needed
- **Test framework**: mini.test (via `deps/mini.nvim`), not plenary
- **Type annotations**: Keep LuaLS annotations (`---@class`, `---@param`, `---@return`, `---@type`, etc.) on every public function and any non-trivial local helper
- **Providers**: Only `openai` / `copilot`
- **Docs**: update `doc/ai-gitcommit.txt`, `README.md`, and `README_CN.md` after user-facing changes
- **Compatibility**: Must work on Linux, macOS, Windows

### Forbidden

- Depending on plenary.nvim
- Expanding the provider list beyond `openai` and `copilot`
  (use OpenAI-compatible endpoints for Ollama / vLLM / local inference instead)
- Removing type annotations
- Introducing new top-level Lua globals (luacheck is invoked with `--globals vim` only)

## Code Style

### Lua

- Tab indentation
- Use `_` for unused variables
- Add LuaLS type annotations to every function parameter, return, and any module-level state that isn't obvious from its initializer

### Type Namespace

All custom LuaLS classes live under the `AIGitCommit.*` namespace. Reuse
existing names before inventing new ones. Current catalog:

| Class                              | Defined in                               | Purpose                                                       |
| ---------------------------------- | ---------------------------------------- | ------------------------------------------------------------- |
| `AIGitCommit.Config`               | `config.lua`                             | Root user-facing configuration                                |
| `AIGitCommit.ProviderConfig`       | `config.lua`                             | Per-provider config block (`providers.openai`, etc.)          |
| `AIGitCommit.ProviderInfo`         | `config.lua`                             | `{ name, config }` returned by `config.get_provider()`        |
| `AIGitCommit.Credentials`          | `config.lua`                             | Resolved `{ api_key, endpoint, model }` passed to `generate`  |
| `AIGitCommit.ContextConfig`        | `config.lua`                             | `context.max_diff_lines` / `max_diff_chars` limits            |
| `AIGitCommit.FilterConfig`         | `config.lua`                             | Include/exclude path/pattern filters                          |
| `AIGitCommit.AutoConfig`           | `config.lua`                             | Auto-generate toggle + debounce                               |
| `AIGitCommit.BufferState`          | `buffer_state.lua`                       | Per-buffer generating/generated/timer state                   |
| `AIGitCommit.StagedFile`           | `git.lua`                                | `{ status, file }` row from `git diff --cached --name-status` |
| `AIGitCommit.PromptOptions`        | `prompt.lua`                             | Input to `prompt.build`                                       |
| `AIGitCommit.StreamRequest`        | `stream.lua`                             | HTTP streaming request descriptor                             |
| `AIGitCommit.StreamHandle`         | `stream.lua`                             | Cancelable stream handle                                      |
| `AIGitCommit.Typewriter`           | `typewriter.lua`                         | Streaming typewriter instance                                 |
| `AIGitCommit.TypewriterOpts`       | `typewriter.lua`                         | Typewriter constructor options                                |
| `AIGitCommit.Provider`             | `providers/init.lua`                     | Provider module interface (generate / credentials)            |
| `AIGitCommit.OpenAICompatOpts`     | `providers/openai_compat.lua`            | Hook table passed to the shared OpenAI-compat generator       |
| `AIGitCommit.AuthModule`           | `auth/init.lua`                          | Auth module interface (get_token / is_authenticated / logout) |
| `AIGitCommit.CopilotTokenData`     | `auth/copilot.lua`                       | Cached Copilot token `{ token, expires_at, endpoint }`        |
| `AIGitCommit.CopilotTokenResult`   | `auth/copilot.lua`                       | Result passed to `get_token` callbacks                        |
| `AIGitCommit.CopilotTokenResponse` | `auth/copilot.lua`                       | Raw `/copilot_internal/v2/token` response                     |
| `AIGitCommit.CopilotModelsCache`   | `auth/copilot.lua`                       | Cached `{ ids, expires_at }` from `/models`                   |

When adding a new type, define it in the module that owns it and prefer the
`AIGitCommit.*` prefix so it is discoverable.

### Commands

Single command `:AICommit` with subcommands (completion provided):

```
:AICommit [context]
:AICommit logout <provider>
:AICommit status [provider]
```

## File Structure

```
lua/ai-gitcommit/
├── init.lua            # Entry wiring (setup/generate)
├── commands.lua        # :AICommit command + completion
├── generator.lua       # Generate pipeline
├── autogen.lua         # FileType gitcommit autocmd + debounce
├── buffer_state.lua    # Per-buffer state
├── config.lua          # Configuration + provider resolution
├── git.lua             # Git operations
├── stream.lua          # HTTP streaming (SSE) via curl + vim.system
├── buffer.lua          # Buffer operations (gitcommit detection, insertion)
├── context.lua         # Diff filtering/truncation
├── prompt.lua          # Prompt template + rendering
├── typewriter.lua      # Streaming text display
├── auth/
│   ├── init.lua        # Auth module registry (copilot only)
│   └── copilot.lua     # Copilot OAuth/token/models resolution
├── providers/
│   ├── init.lua        # Provider registry + status
│   ├── openai.lua      # OpenAI (and OpenAI-compatible) provider
│   ├── copilot.lua     # GitHub Copilot provider
│   └── openai_compat.lua # Shared streaming chat-completions helper
└── util/
    ├── fs.lua          # File read/write helpers
    └── http.lua        # One-shot curl wrapper
plugin/ai-gitcommit.lua # Load guard only
tests/                  # mini.test suites (test_*.lua + helpers.lua)
scripts/minimal_init.lua # Headless init used by `mise run test`
```

## Testing

- Test files in `tests/test_*.lua`
- Use `MiniTest.expect.equality()` (and friends) for assertions
- Shared helpers in `tests/helpers.lua`
- Run all tests: `mise run test`
- Run single file: `mise run test-file tests/test_config.lua`
- `deps/mini.nvim` is auto-cloned by the `deps` mise task; do not commit it
