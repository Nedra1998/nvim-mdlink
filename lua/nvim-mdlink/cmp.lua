local source = {}
local cmp = require("cmp")

source.new = function()
  return setmetatable({ mdlink = nil }, { __index = source })
end

source.is_available = function()
  return vim.bo.filetype == "markdown"
end

source.get_trigger_characters = function()
  return { "[" }
end

source.get_keyword_pattern = function()
  return [=[\%(\s\|^\)\zs\[[^ \]]*\]\?]=]
end

source.execute = function(_, item, callback)
  -- If auto pairs have already added a ']' character then remove that character
  local pos = vim.fn.getcurpos()
  local line = vim.fn.getline(pos[2])
  if line:sub(pos[3], pos[3]) == "]" then
    vim.fn.setline(pos[2], line:sub(0, pos[3] - 1) .. line:sub(pos[3] + 1))
  end
  callback(item)
end

source.complete = function(self, _, callback)
  local bufname = vim.api.nvim_buf_get_name(0)
  local items = {}

  if self.mdlink == nil then
    self.mdlink = require("nvim-mdlink")
  end

  for _, file in pairs(self.mdlink.list.files()) do
    local basename = vim.fn.fnamemodify(file, ":t")
    local name = vim.fn.fnamemodify(basename, ":r")
    local filetype = vim.filetype.match({ filename = file })

    -- Add an entry for every file in the CWD
    table.insert(items, {
      word = "[" .. name,
      label = name,
      insertText = self.mdlink.build_link(name, file),
      filterText = "[" .. name .. "]",
      kind = cmp.lsp.CompletionItemKind.File,
    })

    -- For markdown file also add links for the different sections
    if filetype == "markdown" then
      local headings = self.mdlink.list.headers(file)

      -- For the first heading in the file, add an extra item using the first
      -- heading as an alias to the file
      local first = headings[1]
      if first then
        table.insert(items, {
          word = "[" .. first.key,
          label = first.header,
          insertText = self.mdlink.build_link(first.header, file),
          filterText = "[" .. first.key,
          kind = cmp.lsp.CompletionItemKind.File,
        })
      end

      for _, value in pairs(headings) do
        if file == bufname then
          -- For the current file link the the headings directly without
          -- referencing the filepath
          table.insert(items, {
            word = "[#" .. value.key,
            label = "#" .. value.header,
            insertText = self.mdlink.build_link(value.header, nil, value.key),
            filterText = "[#" .. value.key,
            kind = cmp.lsp.CompletionItemKind.Field,
          })
        else
          -- For other markdown files, create suggestions for every heading in
          -- the file
          table.insert(items, {
            word = "[" .. name .. "#" .. value.key,
            label = name .. "#" .. value.header,
            insertText = self.mdlink.build_link(value.header, file, value.key),
            filterText = "[" .. name .. "#" .. value.key,
            kind = cmp.lsp.CompletionItemKind.Field,
          })
        end
      end
    end
  end

  callback(items)
end

return source
