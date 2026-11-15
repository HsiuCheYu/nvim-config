return {
	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = {
			{ "mason-org/mason.nvim", opts = {} },
			"neovim/nvim-lspconfig",
		},
		opts = {
			ensure_installed = {
				"lua_ls",
				"jsonls",
			},
		},
	},
	{
		"neovim/nvim-lspconfig",
		config = function()
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("UserLspConfig", {}),
				callback = function(ev)
					local bufopts = { noremap = true, silent = true, buffer = ev.buf }
					vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
					vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
					vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
					vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
					vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, bufopts)
					vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, bufopts)
					vim.keymap.set("n", "<space>ca", vim.lsp.buf.code_action, bufopts)
					vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)
				end,
			})
		end,
	},
	{
		{
			"WhoIsSethDaniel/mason-tool-installer.nvim",
			dependencies = { "mason-org/mason.nvim" },
			opts = {
				ensure_installed = {
					"stylua",
					"prettier",
				},
				auto_update = true,
				run_on_start = true,
				start_delay = 3000,
			},
		},
	},
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		opts = {
			formatters_by_ft = {
				lua = { "stylua" },
				json = { "prettier" },
				jsonc = { "prettier" },
			},
		},
		keys = {
			{
				"<leader>fm",
				function()
					require("conform").format({ async = false, lsp_fallback = true })
				end,
				desc = "Format Document",
			},
		},
	},
	{
		-- main 分支:setup() 只管安裝目錄,parser 要自己 install、highlight 要自己啟用
		"nvim-treesitter/nvim-treesitter",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			local ts = require("nvim-treesitter")
			ts.setup({})

			-- parser / filetype 清單與安裝腳本共用 (lua/config/parsers.lua)
			local cfg = require("config.parsers")

			-- 編譯 parser 需要 tree-sitter-cli 與 C 編譯器 (缺少時 config.deps 會在啟動時提醒)
			if vim.fn.executable("tree-sitter") == 1 then
				ts.install(cfg.parsers)
			end

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("UserTreesitterHighlight", {}),
				pattern = cfg.filetypes,
				callback = function(ev)
					-- parser 還沒裝好 (首次啟動,背景安裝中) 時會失敗,忽略即可,重開檔案就會生效
					pcall(vim.treesitter.start, ev.buf)
				end,
			})
		end,
	},
}
