-- nvim-treesitter 要安裝的 parser 與要啟用 highlight 的 filetype。
-- lsp.lua (啟動時) 與 config/bootstrap.lua (安裝腳本) 共用。
return {
	-- jsonc 沒有獨立 parser,filetype 會自動對應到 json
	parsers = { "lua", "rust", "json" },
	filetypes = { "lua", "rust", "json", "jsonc" },
}
