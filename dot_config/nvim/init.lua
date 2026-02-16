-- 基本設定
vim.scriptencoding = 'utf-8'
vim.opt.encoding = 'utf-8'
vim.opt.fileencoding = 'utf-8'

vim.opt.number = true             -- 行番号を表示する
vim.wo.number = true              -- ウィンドウごとに行番号を表示する
vim.wo.relativenumber = false     -- 相対行番号を無効にする
vim.opt.mouse = 'a'               -- すべてのモードでマウス操作を有効にする
vim.opt.title = true              -- ウィンドウタイトルをファイル名などに自動設定する
vim.opt.autoindent = true         -- 自動インデントを有効にする
vim.opt.smartindent = true        -- コード構造に応じたスマートなインデントを有効にする
vim.opt.hlsearch = true           -- 検索結果をハイライト表示する
vim.opt.backup = false            -- バックアップファイルの作成を無効にする
vim.opt.showcmd = true            -- コマンド入力中に部分的なコマンドを表示する
vim.opt.cmdheight = 2             -- コマンドラインの高さを2行に設定する
vim.opt.laststatus = 2            -- 常にステータスラインを表示する
vim.opt.expandtab = true          -- タブをスペースに変換する
vim.opt.scrolloff = 10            -- カーソル周辺に10行分の余白を確保する
vim.opt.shell = 'zsh'             -- 使用するシェルをzshに設定する
vim.opt.inccommand = 'split'      -- インクリメンタルコマンドの結果を分割ウィンドウでプレビューする
vim.opt.ignorecase = true         -- 検索時に大文字と小文字を区別しない
vim.opt.smarttab = true           -- タブ入力時に適切なインデント幅を自動調整する
vim.opt.breakindent = true        -- 折り返し行にもインデントを適用する
vim.opt.shiftwidth = 2            -- 自動インデントの際のスペース幅を2に設定する
vim.opt.tabstop = 2               -- タブの幅を2スペース分に設定する
vim.opt.wrap = true               -- 長い行を画面幅に合わせて折り返して表示する
vim.opt.helplang = 'ja'           -- ヘルプファイルの表示言語を日本語に設定する
vim.opt.updatetime = 300          -- 更新間隔を300ミリ秒に設定し、レスポンスを改善する
vim.opt.showtabline = 2           -- 常にタブラインを表示する
vim.opt.clipboard = 'unnamedplus' -- システムのクリップボードと共有する
vim.opt.termguicolors = true      -- 真のカラーサポートを有効にする
vim.opt.signcolumn = 'yes'        -- サインカラム（デバッグやGit情報表示など）を常に表示する
vim.opt.hidden = true             -- 未保存バッファを隠しバッファとして保持する
vim.opt.swapfile = false          -- スワップファイルの作成を無効にする
vim.opt.list = true               -- 空白やタブなどの特殊文字を表示する
vim.opt.listchars = { tab = '>-', space = '·', trail = '·' }  -- 表示する特殊文字の記号を設定する

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins",
  {
    checker = {enabled = false,},
  }
)

local function is_wsl()
  return vim.loop.os_uname().release:lower():match("microsoft") ~= nil
end

if is_wsl() then
  vim.g.clipboard = {
    name = 'myClipboard',
    copy = {
      ['+'] = 'win32yank.exe -i --crlf',
      ['*'] = 'win32yank.exe -i --crlf',
    },
    paste = {
      ['+'] = 'win32yank.exe -o --lf',
      ['*'] = 'win32yank.exe -o --lf',
    },
   cache_enabled = 1,
  }
end

-- VSCode Neovim環境では使わない設定
if not vim.g.vscode then
  require('catppuccin').setup({
    transparent_background = true,
    custom_highlights = function()
      return {
        TelescopeNormal = { bg = "NONE" },
        TelescopePreviewNormal = { bg = "NONE" },
        TelescopePromptNormal = { bg = "NONE" },
        TelescopeResultsNormal = { bg = "NONE" },
        TelescopeBorder = { bg = "NONE" },
        TelescopePreviewBorder = { bg = "NONE" },
        TelescopePromptBorder = { bg = "NONE" },
        TelescopeResultsBorder = { bg = "NONE" },
      }
    end,
  })
  vim.cmd 'colorscheme catppuccin-mocha'

  require('telescope').setup{
    defaults = {
      vimgrep_arguments = {
        'rg',
        '--color=never',
        '--no-heading',
        '--with-filename',
        '--line-number',
        '--column',
       '--smart-case',
        '-uu' -- **This is the added flag**
      }
    }
  }

  require('gitsigns').setup()

  vim.cmd('syntax enable')
  vim.cmd('filetype plugin indent on')
  vim.g.rustfmt_autosave = 1


  -- C/C++ファイル保存時に、プロジェクトにフォーマット設定(.clang-format)がある場合のみ、
  -- LSP (clangd) の自動フォーマットを実行する設定
  vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = {"*.c", "*.cpp", "*.h", "*.hpp"},  -- 対象のファイル拡張子を指定
    callback = function()
      -- カレントディレクトリから親ディレクトリに向けて、.clang-formatを探す
      -- 末尾の';'によって、上位ディレクトリも検索対象になる
      local config_file = vim.fn.findfile('.clang-format', vim.fn.getcwd() .. ';')

      -- .clang-formatが見つからなければ、フォーマット処理を中断してそのまま保存
      if config_file == "" then
        return
      end

      -- .clang-formatが存在する場合は、LSPのフォーマット機能を同期的に実行する
      vim.lsp.buf.format({ async = false })
    end,
  })


  -- Rust ファイルを保存するたびに LSP で rustfmt を同期実行
  vim.api.nvim_create_autocmd('BufWritePre', {
    pattern = '*.rs',
    callback = function() vim.lsp.buf.format({ async = false }) end,
  })

  -- nvim-cmp setup
  local cmp = require'cmp'

  -- Global setup.
  cmp.setup({
    snippet = {
      expand = function(args)
        vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
        -- require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
        -- require'snippy'.expand_snippet(args.body) -- For `snippy` users.
        -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
        -- vim.snippet.expand(args.body) -- For native neovim snippets (Neovim v0.10+)
      end,
    },
    window = {
      -- completion = cmp.config.window.bordered(),
      -- documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
      -- ['<C-d>'] = cmp.mapping.scroll_docs(-4),
      -- ['<C-f>'] = cmp.mapping.scroll_docs(4),
      -- ['<C-Space>'] = cmp.mapping.complete(),
      ['<CR>'] = cmp.mapping.confirm({ select = true }),
    }),
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'vsnip' }, -- For vsnip users.
      -- { name = 'luasnip' }, -- For luasnip users.
      -- { name = 'snippy' }, -- For snippy users.
      -- { name = 'ultisnips' }, -- For ultisnips users.
    }, {
      { name = 'buffer' },
    })
  })

  -- `/` cmdline setup.
  cmp.setup.cmdline('/', {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
      { name = 'buffer' }
    }
  })

  -- `:` cmdline setup.
  cmp.setup.cmdline(':', {
    mapping = cmp.mapping.preset.cmdline(),
    sources = cmp.config.sources({
      { name = 'path' }
    }, {
      { name = 'cmdline' }
    }),
    matching = { disallow_symbol_nonprefix_matching = false }
  })

  
  -- init.lua の例
  vim.opt.completeopt = {
    "menuone",   -- 候補が1件でもメニューを表示
    "noselect",  -- 自動選択を無効化
    "noinsert",  -- 自動挿入を無効化
    "popup",     -- 浮動ウィンドウ形式のメニューを有効化
  }

  -- LSP config
  -- It's important that you set up the plugins in the following order:
  --
  -- 1. Mason 本体セットアップ
  require("mason").setup()

  -- 2. mason-lspconfig セットアップ
  require("mason-lspconfig").setup({
    ensure_installed      = {
      "lua_ls", "clangd", "rust_analyzer",
      "julials", "tinymist", "typos_lsp", "pyright",
    },
    -- automatic_enable = true (デフォルト)
  })

  -- 3. capabilities をグローバルに設定
  local caps = require("cmp_nvim_lsp").default_capabilities()
  vim.lsp.config('*', {
    capabilities = caps,
  })

  -- 4. LspAttach autocmd（on_attach 相当）
  vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(ev)
      -- キーマッピングなどの設定（必要に応じて追加）
    end,
  })

  -- 5. サーバーごとの追加設定
  -- Lua
  vim.lsp.config('lua_ls', {
    settings = {
      Lua = {
        diagnostics = {
          globals = { "vim" },
        },
      },
    },
  })

  -- Clangd
  vim.lsp.config('clangd', {
    cmd = { "clangd", "--offset-encoding=utf-16" },
  })

  -- typos_lsp
  vim.lsp.config('typos_lsp', {
    init_options = {
      config = vim.fn.expand("~/.config/nvim/spell/.typos.toml"),
    },
  })

  -- Rust Analyzer（めちゃくちゃ重くなることがあるので、procMacro無効 + cargo check のみにする）
  vim.lsp.config('rust_analyzer', {
    settings = {
      ["rust-analyzer"] = {
        procMacro = {
          enable = true,
        },
        checkOnSave = true, -- boolean型に変更
        check = {
          command = "check", -- "clippy" は重いので "check" のみに
        },
        diagnostics = {
          disabled = { "unresolved-proc-macro" }, -- よく出る false positive を抑える
        },
      },
    },
  })

  -- 6. LSPサーバーを有効化
  vim.lsp.enable({
    'lua_ls', 'clangd', 'rust_analyzer',
    'julials', 'tinymist', 'typos_lsp', 'pyright'
  })

  -- setup additional plugins about lsp
  require("fidget").setup()

  -- nvim-treesitter セットアップ（main ブランチ新 API）
  local ts = require('nvim-treesitter')
  ts.setup()

  -- パーサーのインストール
  ts.install({
    'c', 'lua', 'vim', 'vimdoc', 'query',
    'markdown', 'markdown_inline',
    'rust', 'cpp', 'python', 'julia', 'typst',
  })

  -- ハイライト有効化（Neovim 組み込み API）
  vim.api.nvim_create_autocmd('FileType', {
    pattern = '*',
    callback = function(ev)
      pcall(vim.treesitter.start, ev.buf)
    end,
  })
end

-- copilot chat
local select = require('CopilotChat.select')
local columns = vim.o.columns - (vim.o.columns * 0.4) - 3 -- 2はボーダーの分
require('CopilotChat').setup({
  -- Shared config starts here (can be passed to functions at runtime and configured via setup function)

  system_prompt = 'COPILOT_INSTRUCTIONS', -- System prompt to use (can be specified manually in prompt via /).

  model = 'o4-mini', -- Default model to use, see ':CopilotChatModels' for available models (can be specified manually in prompt via $).
  agent = 'copilot', -- Default agent to use, see ':CopilotChatAgents' for available agents (can be specified manually in prompt via @).
  context = nil, -- Default context or array of contexts to use (can be specified manually in prompt via #).
  sticky = nil, -- Default sticky prompt or array of sticky prompts to use at start of every new chat.

  temperature = 0.1, -- GPT result temperature
  headless = false, -- Do not write to chat buffer and use history (useful for using custom processing)
  stream = nil, -- Function called when receiving stream updates (returned string is appended to the chat buffer)
  callback = nil, -- Function called when full response is received (returned string is stored to history)
  remember_as_sticky = true, -- Remember model/agent/context as sticky prompts when asking questions

  -- default selection
  -- see select.lua for implementation
  selection = select.visual,

  -- default window options

  window = {
    layout = 'float', -- 'vertical'から'float'に変更
    width = 0.4, -- 幅を少し小さめに
    height = 0.8, -- 高さを大きめに
    -- フローティングウィンドウのオプション
    relative = 'editor',
    border = 'rounded',
    row = 1, -- 上端から1行下
    col = columns, -- 画面の右端に表示
    title = 'Copilot Chat',
    footer = nil,
    zindex = 1,
  },

  show_help = true, -- Shows help message as virtual lines when waiting for user input
  highlight_selection = true, -- Highlight selection
  highlight_headers = true, -- Highlight headers in chat, disable if using markdown renderers (like render-markdown.nvim)
  references_display = 'virtual', -- 'virtual', 'write', Display references in chat as virtual text or write to buffer
  auto_follow_cursor = true, -- Auto-follow cursor in chat
  auto_insert_mode = false, -- Automatically enter insert mode when opening window and on new prompt
  insert_at_end = false, -- Move cursor to end of buffer when inserting text
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt

  -- Static config starts here (can be configured only via setup function)

  debug = false, -- Enable debug logging (same as 'log_level = 'debug')
  log_level = 'info', -- Log level to use, 'trace', 'debug', 'info', 'warn', 'error', 'fatal'
  proxy = nil, -- [protocol://]host[:port] Use this proxy
  allow_insecure = false, -- Allow insecure server connections

  chat_autocomplete = true, -- Enable chat autocompletion (when disabled, requires manual `mappings.complete` trigger)

  log_path = vim.fn.stdpath('state') .. '/CopilotChat.log', -- Default path to log file
  history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history

  question_header = '# User ', -- Header to use for user questions
  answer_header = '# Copilot ', -- Header to use for AI answers
  error_header = '# Error ', -- Header to use for errors
  separator = '───', -- Separator to use in chat

  -- default providers
  -- see config/providers.lua for implementation
  providers = {
    copilot = {
    },
    github_models = {
    },
    copilot_embeddings = {
    },
  },

  -- default contexts
  -- see config/contexts.lua for implementation
  contexts = {
    buffer = {
    },
    buffers = {
    },
    file = {
    },
    files = {
    },
    git = {
    },
    url = {
    },
    register = {
    },
    quickfix = {
    },
    system = {
    }
  },

  -- default prompts
  -- see config/prompts.lua for implementation
  prompts = {
    Explain = {
      prompt = "/COPILOT_EXPLAIN コードを日本語で説明してください",
      mapping = '<leader>ce',
      description = "コードの説明をお願いする",
    },
    Review = {
      prompt = '/COPILOT_REVIEW コードを日本語でレビューしてください。',
      mapping = '<leader>cr',
      description = "コードのレビューをお願いする",
    },
    Fix = {
      prompt = "/COPILOT_FIX このコードには問題があります。バグを修正したコードを表示してください。説明は日本語でお願いします。",
      mapping = '<leader>cf',
      description = "コードの修正をお願いする",
    },
    Optimize = {
      prompt = "/COPILOT_REFACTOR 選択したコードを最適化し、パフォーマンスと可読性を向上させてください。説明は日本語でお願いします。",
      mapping = '<leader>co',
      description = "コードの最適化をお願いする",
    },
    Docs = {
      prompt = "/COPILOT_GENERATE 選択したコードに関するドキュメントコメントを日本語で生成してください。",
      mapping = '<leader>cd',
      description = "コードのドキュメント作成をお願いする",
    },
    Tests = {
      prompt = "/COPILOT_TESTS 選択したコードの詳細なユニットテストを書いてください。説明は日本語でお願いします。",
      mapping = '<leader>ct',
      description = "テストコード作成をお願いする",
    },
    FixDiagnostic = {
      prompt = 'コードの診断結果に従って問題を修正してください。修正内容の説明は日本語でお願いします。',
      mapping = '<leader>cd',
      description = "コードの修正をお願いする",
      selection = require('CopilotChat.select').diagnostics,
    },
    Commit = {
      prompt =
      '実装差分に対するコミットメッセージを日本語で記述してください。',
      mapping = '<leader>cco',
      description = "コミットメッセージの作成をお願いする",
      selection = require('CopilotChat.select').gitdiff,
    },
    CommitStaged = {
      prompt =
      'ステージ済みの変更に対するコミットメッセージを日本語で記述してください。',
      mapping = '<leader>cs',
      description = "ステージ済みのコミットメッセージの作成をお願いする",
      selection = function(source)
          return require('CopilotChat.select').gitdiff(source, true)
      end,
    },
    },

  -- default mappings
  -- see config/mappings.lua for implementation
  mappings = {
    complete = {
      insert = '<Tab>',
    },
    close = {
      normal = 'q',
      insert = '<C-c>',
    },
    reset = {
      normal = '<C-l>',
      insert = '<C-l>',
    },
    submit_prompt = {
      normal = '<CR>',
      insert = '<C-s>',
    },
    toggle_sticky = {
      normal = 'grr',
    },
    clear_stickies = {
      normal = 'grx',
    },
    accept_diff = {
      normal = '<C-y>',
      insert = '<C-y>',
    },
    jump_to_diff = {
      normal = 'gj',
    },
    quickfix_answers = {
      normal = 'gqa',
    },
    quickfix_diffs = {
      normal = 'gqd',
    },
    yank_diff = {
      normal = 'gy',
      register = '"', -- Default register to use for yanking
    },
    show_diff = {
      normal = 'gd',
      full_diff = false, -- Show full diff instead of unified diff when showing diff window
    },
    show_info = {
      normal = 'gi',
    },
    show_context = {
      normal = 'gc',
    },
    show_help = {
      normal = 'gh',
    },
  },
})

vim.keymap.set('x', '<leader>cc', function()
  require('CopilotChat').open()
end, {
  desc = "選択範囲をコンテキストに Copilot Chat（空プロンプト）を開く"
})

-- keymap
-- Native Neovim, VSCode Neovim共通のキーバインド
vim.keymap.set('n', '<C-j>', '<Cmd>BufferPrevious<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<C-k>', '<Cmd>BufferNext<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>e', '<Cmd>BufferClose<CR>', { noremap = true, silent = true })
vim.keymap.set({'v', 'n'}, '<leader>gl', ':GetCommitLink<CR>')

-- VSCode Neovimだけで使うもの
if vim.g.vscode then
  vim.keymap.set('n', '<leader>ff', function()
    require('vscode').call('find-it-faster.findFiles')
  end, { noremap = true, silent = true })
-- Native Neovimだけで使うもの
else
  -- insert modeからの離脱
  vim.keymap.set('i', 'jj', '<ESC>', { noremap = true, silent = true })

  -- window split
  vim.keymap.set('n', 'ss', ':split<Return><C-w>w')
  vim.keymap.set('n', 'sv', ':vsplit<Return><C-w>w')
  vim.keymap.set('n', 'sh', '<C-w>h')
  vim.keymap.set('n', 'sk', '<C-w>k')
  vim.keymap.set('n', 'sj', '<C-w>j')
  vim.keymap.set('n', 'sl', '<C-w>l')

  -- floating windownとの行き来
  local function toggle_floating_win()
    local cur = vim.api.nvim_get_current_win()
    -- floating windowを抽出する
    -- floating windowの数は実用上せいぜい1つ程度なので、最初に見つけたものを返す
    local float_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        float_win = win
        break
      end
    end

    -- floating windowがなければ何もしない
    if not float_win or not vim.api.nvim_win_is_valid(float_win) then
      return
    end

    if cur == float_win then
      -- 現在floating window上なら、直前のウィンドウに戻る
      vim.cmd("wincmd p")
    else
      -- それ以外ならfloating windowに移動
      vim.api.nvim_set_current_win(float_win)
    end
  end

  vim.keymap.set("n", "sf", toggle_floating_win)

  -- Telescope
  local builtin = require('telescope.builtin')
  vim.api.nvim_set_keymap('n', '<leader>ff', ':Telescope find_files find_command=rg,--files,--hidden,--glob,!*.git <CR>', { noremap = true, silent = true })
  vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
  vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
  vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
  vim.keymap.set('n', '<leader>fq', builtin.quickfix, {})

  vim.api.nvim_set_keymap('i', '<Tab>', 'vsnip#jumpable(1) ? "<Plug>(vsnip-jump-next)" : "<Tab>"', {expr = true, noremap = true})
  vim.api.nvim_set_keymap('s', '<Tab>', 'vsnip#jumpable(1) ? "<Plug>(vsnip-jump-next)" : "<Tab>"', {expr = true, noremap = true})
  vim.api.nvim_set_keymap('i', '<S-Tab>', 'vsnip#jumpable(-1) ? "<Plug>(vsnip-jump-prev)" : "<S-Tab>"', {expr = true, noremap = true})
  vim.api.nvim_set_keymap('s', '<S-Tab>', 'vsnip#jumpable(-1) ? "<Plug>(vsnip-jump-prev)" : "<S-Tab>"', {expr = true, noremap = true})

  -- keymaps about lsp
  vim.keymap.set('n', '<space>e', vim.diagnostic.open_float, { noremap=true, silent=true })
  vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { noremap=true, silent=true })
  vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { noremap=true, silent=true })

  vim.keymap.set('n', 'K', '<cmd>Lspsaga hover_doc<CR>')
  vim.keymap.set("n", "ga", "<cmd>Lspsaga code_action<CR>")
  vim.keymap.set('n', 'gr', '<cmd>Lspsaga lsp_finder<CR>')
  vim.keymap.set("n", "gd", "<cmd>Lspsaga peek_definition<CR>")
  vim.keymap.set("n", "gn", "<cmd>Lspsaga rename<CR>")
  vim.keymap.set("n", "ge", "<cmd>Lspsaga show_line_diagnostics<CR>")
  vim.keymap.set("n", "gw", "<cmd>Lspsaga show_workspace_diagnostics<CR>")
  vim.keymap.set("n", "[e", "<cmd>Lspsaga diagnostic_jump_next<CR>")
  vim.keymap.set("n", "]e", "<cmd>Lspsaga diagnostic_jump_prev<CR>")

  -- quickfix

  -- <leader>qdで、今出ているdiagnosticをquickfixに詰め込む
  vim.api.nvim_create_user_command('DiagnosticsQf', function()
    vim.diagnostic.setqflist({ open = true })
  end, {})
  vim.keymap.set('n', '<leader>qd', '<cmd>DiagnosticsQf<CR>', { noremap=true, silent=true })

  -- quickfix bufferの中で <CR>を押すと、Lspsagaのcode_actionを実行する
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'qf',
    callback = function()
      vim.keymap.set('n', '<CR>', '<cmd>Lspsaga code_action<CR>', {
        buffer = true,
        noremap = true,
        silent = true,
      })
    end,
  })
  
  -- 現在のバッファのパスをyankするキーバインド
  vim.keymap.set('n', '<leader>cy', function()
    local path = vim.fn.expand('%:p')
    vim.fn.setreg('+', path)
    vim.notify('Copied: ' .. path)
  end, { desc = 'Copy buffer path to clipboard' })
end
