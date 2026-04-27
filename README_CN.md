# ai-gitcommit.nvim

AI 驱动的 Neovim git commit 信息生成器。

支持的 Provider：
- OpenAI（及兼容接口）
- GitHub Copilot

## 依赖

- Neovim 0.11+
- curl
- OpenAI API key，或 [copilot.vim](https://github.com/github/copilot.vim) / [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

## 安装

```lua
-- lazy.nvim（Copilot —— 默认，已安装 copilot.vim/copilot.lua 即无需任何配置）
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
    languages = { "Chinese", "English" },
  },
}
```

## 使用

```vim
:AICommit                       " 生成 commit message
:AICommit [附加说明]             " 带上下文生成
:AICommit logout <provider>     " 清除认证状态
:AICommit status                " 查看全部 provider 状态
:AICommit status <provider>     " 查看单个 provider 状态
```

## 配置

```lua
require("ai-gitcommit").setup({
  provider = "copilot", -- "openai" | "copilot"（默认: "copilot"）

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
      -- model = nil → 自动从 /models 选最便宜可用模型
      -- 若要固定某个模型，设置成字符串，如 "gpt-4o" 或 "claude-sonnet-4"
      model = nil,
      endpoint = "https://api.githubcopilot.com/chat/completions",
      max_tokens = 500,
    },
  },

  languages = { "Chinese", "English" },
  prompt_template = nil, -- 字符串或 function(default_prompt) -> string
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

Copilot provider 直接读取已安装的 Copilot 插件的 OAuth token —— **无需单独登录**。

### 前提条件

安装并认证以下插件之一：
- [copilot.vim](https://github.com/github/copilot.vim) — 运行 `:Copilot auth`
- [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

认证完成后，`ai-gitcommit.nvim` 会自动检测 token。

### 模型选择

默认情况下，插件会通过 Copilot 的 `/models` endpoint 自动检测你订阅能用的所有
chat 模型，并**自动选择 `billing.multiplier` 最低的那个** —— 也就是你可用的
最便宜模型。典型结果：`grok-code-fast-1` 或 `gpt-4o-mini`（大多数套餐上是 `0x`）。

解析出来的模型列表在内存里缓存 30 分钟。

若要固定某个模型，显式配置：

```lua
providers = {
  copilot = {
    model = "claude-sonnet-4",
  },
},
```

常见可用模型（取决于订阅：Free / Pro / Pro+ / Business / Enterprise）：
`grok-code-fast-1`、`gpt-4.1`、`gpt-4o`、`gpt-4o-mini`、`claude-sonnet-4`、
`o3-mini`、`o4-mini`…

## OpenAI 兼容接口

使用 `openai` provider 配合自定义 endpoint：

```lua
providers = {
  openai = {
    endpoint = "http://localhost:11434/v1/chat/completions",
    api_key_required = false, -- 本地服务无需鉴权
    model = "llama3",
  },
},
```

- 非 Bearer 鉴权：配置 `api_key_header` 和 `api_key_prefix`
- 额外请求头：使用 `extra_headers`
- 若服务不支持 OpenAI `stream_options`：设置 `stream_options = false`

## 自定义 Prompt 模板

占位符：`{language}`、`{extra_context}`、`{staged_files}`、`{diff}`

`prompt_template` 可以是字符串，也可以是接收默认 prompt 并返回新字符串的函数。

```lua
prompt_template = [[
为以下更改生成 commit message。
使用 {language} 语言，简洁明了。

{extra_context}

文件: {staged_files}

Diff:
{diff}

只输出 commit message，不要解释。
]]
```

## Diff 上下文行为

- `filter.exclude_patterns` — 按文件名模式排除文件
- `filter.exclude_paths` — 按路径模式排除文件
- `filter.include_only` — 非空时仅保留匹配的文件
- 上下文先按 `context.max_diff_lines` 截断，再按 `context.max_diff_chars` 截断
- 默认排除规则覆盖常见 lockfile、sourcemap / minified 产物，以及 protobuf / GORM gen / Connect RPC 生成文件

## 生成行为

- `:AICommit` 只能在 `gitcommit` buffer 中使用
- 默认基于已暂存的改动生成
- 在 `git commit --amend` 场景下，如果当前 buffer 已有旧 message 且没有新的 staged changes，会回退到当前 `HEAD` commit 的 diff 作为生成上下文
- 当配置了多个 `languages` 时，会弹出语言选择器
- 当 `auto.enabled = true` 时，会在 `FileType gitcommit` 后等待 `debounce_ms` 自动触发生成，但前提是 provider 凭证已经可用

## License

MIT
