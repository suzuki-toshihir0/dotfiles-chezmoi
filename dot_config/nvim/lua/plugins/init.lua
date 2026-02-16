local is_vscode_neovim = vim.g.vscode

-- Native NeovimでもVSCode Neovimでも使うプラグイン一覧
local common_plugins = {
  {"folke/lazy.nvim"},
  {"lambdalisue/nerdfont.vim"},
  {"github/copilot.vim"},
  {"knsh14/vim-github-link"},
}

-- VSCode Neovimだと動かないのでNative Neovimでだけ使いたいもの
local non_vscode_neovim_plugins = {
  {'lambdalisue/fern.vim',
    keys = {
      { "<C-n>", ":Fern . -reveal=% -drawer -toggle -width=40<CR>", desc = "toggle fern" },
    },
    dependencies = {
      { 'lambdalisue/nerdfont.vim', },
      { 'lambdalisue/fern-renderer-nerdfont.vim',
        config = function()
          vim.g['fern#renderer'] = "nerdfont"
          vim.g['fern#default_hidden'] = 1
        end
      },
      { 'lambdalisue/fern-git-status.vim', },
    },
  },
  {"nvim-telescope/telescope.nvim", dependencies = {"nvim-lua/plenary.nvim"}},
  {'romgrk/barbar.nvim',
    dependencies = {
      'lewis6991/gitsigns.nvim', -- OPTIONAL: for git status
      'nvim-tree/nvim-web-devicons', -- OPTIONAL: for file icons
    },
    init = function() vim.g.barbar_auto_setup = false end,
    opts = {
      -- lazy.nvim will automatically call setup for you. put your options here, anything missing will use the default:
      -- animation = true,
      -- insert_at_start = true,
      -- …etc.
    },
    version = '^1.0.0', -- optional: only update when a new 1.x version is released
  },
  {"catppuccin/nvim", name = "catppuccin", priority = 1000},
  {"sindrets/diffview.nvim"},
  {"rust-lang/rust.vim"},
  {"JuliaEditorSupport/julia-vim"},
  -- treesitter
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    build = ':TSUpdate',
  },
  -- lsp
  {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "neovim/nvim-lspconfig",
  },
  -- additional plugins about lsp
  {"j-hui/fidget.nvim"},
  {"nvimdev/lspsaga.nvim",
    config = function()
        require('lspsaga').setup({})
    end,
    dependencies = {'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons'}
  },
  {
    "hrsh7th/vim-vsnip",
    config = function()
      -- スニペットファイルの保存場所を設定
      vim.g.vsnip_snippet_dir = vim.fn.stdpath('config') .. '/snippets'
    end,
  },
  {'hrsh7th/cmp-nvim-lsp'},
  {'hrsh7th/cmp-buffer'},
  {'hrsh7th/cmp-path'},
  {'hrsh7th/cmp-cmdline'},
  {'hrsh7th/nvim-cmp'},
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "github/copilot.vim" }, -- or zbirenbaum/copilot.lua
      { "nvim-lua/plenary.nvim", branch = "master" }, -- for curl, log and async functions
    },
    build = "make tiktoken", -- Only on MacOS or Linux
    opts = {
      -- See Configuration section for options
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
}

-- この環境で読み込むプラグイン一覧
local plugins = {}

-- まず共通プラグインをプラグイン一覧に追加
for _, plugin in ipairs(common_plugins) do
  table.insert(plugins, plugin)
end

-- そのあと、VSCode NeovimでなければNative Neovimでだけ使いたいプラグインを追加
if not is_vscode_neovim then
  for _, plugin in ipairs(non_vscode_neovim_plugins) do
    table.insert(plugins, plugin)
  end
end

return plugins
