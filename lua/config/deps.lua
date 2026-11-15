-- 外部依賴清單與檢查 (macOS / Linux)。
--   * 啟動時只檢查「必要」工具,缺少就提醒一次
--   * :Deps 等同 :checkhealth config,列出完整狀態(含版本、選用工具)
--   * 安裝請執行 install.sh
--
-- 停用啟動檢查:vim.g.deps_check = false

local M = {}

-- 與 lazy-lock.json 鎖定的 nvim-treesitter (main 分支) 要求一致
M.min_nvim = "0.12"

---@class config.Dep
---@field name string
---@field bins string[]       任一個存在即視為已安裝(例如 Ubuntu 的 fd 叫 fdfind)
---@field why string          用途 / 哪個外掛需要
---@field required? boolean   true: 缺少會影響核心功能
---@field version? { args: string[], min: string }

---@type config.Dep[]
local deps = {
	{ name = "git", bins = { "git" }, required = true, why = "lazy.nvim 安裝/更新外掛、gitsigns" },
	{ name = "curl", bins = { "curl" }, required = true, why = "nvim-treesitter 與 Mason 下載檔案、smart-translate" },
	{ name = "tar", bins = { "tar" }, required = true, why = "nvim-treesitter 與 Mason 解壓縮" },
	{ name = "unzip", bins = { "unzip" }, required = true, why = "Mason 解壓縮套件" },
	{ name = "gzip", bins = { "gzip" }, required = true, why = "Mason 解壓縮套件" },
	{ name = "C compiler", bins = { "cc", "gcc", "clang" }, required = true, why = "nvim-treesitter 編譯 parser (macOS: Xcode CLT)" },
	{ name = "make", bins = { "make" }, required = true, why = "telescope-fzf-native 的 build 步驟" },
	{
		name = "tree-sitter",
		bins = { "tree-sitter" },
		required = true,
		why = "nvim-treesitter (main) 產生 parser,需 0.26.1+ 且不可用 npm 版",
		version = { args = { "--version" }, min = "0.26.1" },
	},
	{ name = "ripgrep", bins = { "rg" }, required = true, why = "Telescope live_grep、Snacks picker grep" },
	{ name = "npm", bins = { "npm" }, required = true, why = "Mason 以 npm 安裝 prettier / jsonls (隨 Node.js 附帶)" },
	{ name = "fd", bins = { "fd", "fdfind" }, why = "Telescope find_files、Snacks explorer 更快(沒有則退回 rg/find)" },
	{ name = "lazygit", bins = { "lazygit" }, why = "<leader>gg 開啟 lazygit" },
	{ name = "cargo", bins = { "cargo" }, why = "Rust 專案 (rustaceanvim、crates.nvim)" },
	{ name = "rust-analyzer", bins = { "rust-analyzer" }, why = "Rust LSP (rustup component add rust-analyzer)" },
	{ name = "clippy", bins = { "cargo-clippy" }, why = "rust-analyzer 的 check.command = clippy" },
}

---@return config.Dep[]
function M.list()
	return deps
end

---回傳第一個找到的執行檔名稱,沒有則回傳 nil
---@param dep config.Dep
---@return string?
function M.find(dep)
	for _, bin in ipairs(dep.bins) do
		if vim.fn.executable(bin) == 1 then
			return bin
		end
	end
end

---執行 `bin --version` 並解析出版本號
---@param dep config.Dep
---@param bin string
---@return vim.Version?
function M.version(dep, bin)
	if not dep.version then
		return
	end
	local ok, proc = pcall(vim.system, vim.list_extend({ bin }, dep.version.args), { text = true })
	if not ok then
		return
	end
	local res = proc:wait(3000)
	return vim.version.parse((res.stdout or "") .. (res.stderr or ""), { strict = false })
end

---@return string
function M.install_hint()
	return ("bash %s/install.sh"):format(vim.fn.stdpath("config"))
end

---@return config.Dep[] missing  缺少的必要工具
function M.missing_required()
	local missing = {}
	for _, d in ipairs(deps) do
		if d.required and not M.find(d) then
			missing[#missing + 1] = d
		end
	end
	return missing
end

function M.check()
	local msgs = {}

	if vim.fn.has("nvim-" .. M.min_nvim) == 0 then
		local v = vim.version()
		msgs[#msgs + 1] = ("Neovim %d.%d.%d 太舊,需要 %s 以上 (nvim-treesitter main)"):format(
			v.major,
			v.minor,
			v.patch,
			M.min_nvim
		)
	end

	local missing = M.missing_required()
	if #missing > 0 then
		msgs[#msgs + 1] = "缺少必要工具:"
			.. table.concat(
				vim.tbl_map(function(d)
					return d.name
				end, missing),
				", "
			)
	end

	if #msgs == 0 then
		return
	end
	msgs[#msgs + 1] = "安裝:" .. M.install_hint()
	msgs[#msgs + 1] = "完整報告::Deps"
	vim.notify(table.concat(msgs, "\n"), vim.log.levels.WARN, { title = "nvim-config" })
end

function M.setup()
	vim.api.nvim_create_user_command("Deps", "checkhealth config", { desc = "檢查外部依賴" })

	-- headless 模式 (例如 install.sh 跑 Lazy! sync) 不需要提醒
	if vim.g.deps_check == false or #vim.api.nvim_list_uis() == 0 then
		return
	end
	vim.api.nvim_create_autocmd("VimEnter", {
		once = true,
		callback = vim.schedule_wrap(M.check),
	})
end

return M
