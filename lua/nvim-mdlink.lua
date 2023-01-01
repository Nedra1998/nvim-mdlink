local M = {}

M.config = {}

M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
end
