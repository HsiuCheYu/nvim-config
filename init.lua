require("config.options")
require("config.deps").setup()
require("config.lazy")

vim.diagnostic.config({
	virtual_text = {
		spacing = 4,
	},
})

vim.api.nvim_set_hl(0, "rustTodo", { link = "Comment" })
