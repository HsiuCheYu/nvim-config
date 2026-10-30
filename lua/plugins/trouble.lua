return {
	{
		"folke/trouble.nvim",
		opts = {},
		cmd = "Trouble",
		keys = (function()
			local function copy_diagnostics(diagnostics, scope)
				if #diagnostics == 0 then
					vim.notify("No diagnostics" .. (scope and " on " .. scope or "") .. " to copy!")
					return
				end
				local lines = vim.tbl_map(function(d)
					return string.format("[Line %d, Col %d] %s", d.lnum + 1, d.col + 1, d.message)
				end, diagnostics)
				vim.fn.setreg("+", table.concat(lines, "\n"))
				vim.notify(string.format("Copied %d diagnostic(s)%s", #diagnostics, scope and " from " .. scope or ""))
			end

			return {
				{
					"<leader>ec",
					function()
						copy_diagnostics(vim.diagnostic.get(0))
					end,
					desc = "Copy all diagnostics",
				},
				{
					"<leader>el",
					function()
						local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
						copy_diagnostics(vim.diagnostic.get(0, { lnum = lnum }), "current line")
					end,
					desc = "Copy line diagnostics",
				},
			}
		end)(),
	},
}
