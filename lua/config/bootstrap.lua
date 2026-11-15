-- 讓 install 腳本在 headless 模式下,把需要「背景下載」的東西同步裝完:
--   nvim --headless "+lua require('config.bootstrap').run()" +qa
-- (外掛本身由 `nvim --headless "+Lazy! sync" +qa` 先裝好)
local M = {}

local MINUTE = 60 * 1000

local function install_parsers()
	local ok, ts = pcall(require, "nvim-treesitter")
	if not ok then
		return print("bootstrap: nvim-treesitter 尚未安裝,略過 parser")
	end
	if vim.fn.executable("tree-sitter") == 0 then
		return print("bootstrap: 找不到 tree-sitter-cli,略過 parser")
	end
	print("bootstrap: 安裝 treesitter parser ...")
	ts.install(require("config.parsers").parsers):wait(10 * MINUTE)
end

local function install_mason()
	local ok, registry = pcall(require, "mason-registry")
	if not ok then
		return print("bootstrap: mason 尚未安裝,略過 LSP / formatter")
	end
	print("bootstrap: 安裝 Mason 套件 (LSP / formatter) ...")
	-- registry 要先從 GitHub 下載;網路不通時 MasonToolsInstallSync 會一直等,所以先確認它可用
	local loaded = vim.wait(60 * 1000, function()
		local names_ok, names = pcall(registry.get_all_package_names)
		return names_ok and #names > 0
	end, 500)
	if not loaded then
		return print("bootstrap: Mason registry 下載失敗 (網路?),略過。之後開啟 nvim 會自動重試")
	end
	-- mason-tool-installer (stylua, prettier);指令不存在就略過
	pcall(vim.cmd, "MasonToolsInstallSync")
	-- mason-lspconfig 的 ensure_installed 是背景作業,等到沒有任何套件在安裝為止
	vim.wait(8000)
	vim.wait(10 * MINUTE, function()
		for _, pkg in ipairs(registry.get_all_packages()) do
			if pkg:is_installing() then
				return false
			end
		end
		return true
	end, 500)
end

function M.run()
	-- 保險:任何一步卡住超過 20 分鐘就放棄,不讓安裝腳本無限等待
	local watchdog = vim.uv.new_timer()
	watchdog:start(20 * MINUTE, 0, vim.schedule_wrap(function()
		print("bootstrap: 逾時,中止 (已完成的部分不受影響,開啟 nvim 會繼續補齊)")
		vim.cmd("cquit 1")
	end))
	install_parsers()
	install_mason()
	watchdog:stop()
	print("bootstrap: 完成")
end

return M
