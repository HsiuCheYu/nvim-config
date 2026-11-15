require("config.options")
require("config.deps").setup()
require("config.lazy")

vim.diagnostic.config({
	virtual_text = {
		spacing = 4,
	},
})
