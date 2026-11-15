-- :checkhealth config (或 :Deps)
local deps = require("config.deps")

local M = {}

function M.check()
	vim.health.start("Neovim")
	if vim.fn.has("nvim-" .. deps.min_nvim) == 1 then
		local v = vim.version()
		vim.health.ok(("Neovim %d.%d.%d (需要 >= %s)"):format(v.major, v.minor, v.patch, deps.min_nvim))
	else
		vim.health.error("Neovim 版本過舊,需要 >= " .. deps.min_nvim, { "請升級 Neovim", deps.install_hint() })
	end

	vim.health.start("外部工具 (" .. deps.os .. ")")
	for _, dep in ipairs(deps.list()) do
		local bin = deps.find(dep)
		if not bin then
			local report = dep.required and vim.health.error or vim.health.warn
			report(("%s 未安裝 — %s"):format(dep.name, dep.why), { deps.install_hint() })
		else
			local v = deps.version(dep, bin)
			if dep.version and not v then
				vim.health.warn(("%s 找到 (%s) 但無法判斷版本,需要 >= %s"):format(dep.name, bin, dep.version.min))
			elseif v and vim.version.lt(v, dep.version.min) then
				vim.health.error(
					("%s %s 太舊,需要 >= %s — %s"):format(dep.name, tostring(v), dep.version.min, dep.why),
					{ deps.install_hint() }
				)
			else
				vim.health.ok(("%s (%s%s) — %s"):format(dep.name, bin, v and (" " .. tostring(v)) or "", dep.why))
			end
		end
	end

	vim.health.start("其他")
	vim.health.info("mini.icons 需要終端機使用 Nerd Font (無法自動偵測,圖示顯示成方框請自行安裝)")
	vim.health.info("copilot.lua 首次使用請執行 :Copilot auth 登入")
end

return M
