local source = {}
local cmp = require("cmp")

local LINK_REGEX = [=[%[([^#]*)#?$]=]

source.new = function()
  return setmetatable({ mdlink = nil }, { __index = source })
end

source.is_available = function()
  return vim.bo.filetype == "markdown"
end

source.get_trigger_characters = function()
  return { "[", "#" }
end

source.get_keyword_pattern = function()
  return [=[\%(\s\|^\)\zs\[[^ \]]*\]\?]=]
end

source.resolve = function(self, item, callback)
  -- When the completion item is selected (before executed), if it is a file
  -- link and the file is a markdown file then parse the headers and use the
  -- first header as the link text.
  if item.data ~= nil and item.data.file ~= nil then
    local filetype = vim.filetype.match({ filename = item.data.file })

    if filetype == "markdown" then
      local headings = self.mdlink.list.headers(item.data.file)
      local first = headings[1]
      if first then
        item.insertText = self.mdlink.build_link(first.header, item.data.file)
      end
    end
  end
  callback(item)
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

source.complete = function(self, params, callback)
  if self.mdlink == nil then
    self.mdlink = require("nvim-mdlink")
  end

  local items = {}

  local m = params.context.cursor_before_line:match(LINK_REGEX)
  if m ~= nil then
    if params.context.cursor_before_line:sub(-1) ~= "#" then
      items = self._file_canidates(self)
    else
      items = self._heading_canidates(self, m)
    end
  end
  callback(items)
end

source._file_canidates = function(self)
  local items = {}

  for _, file in pairs(self.mdlink.list.files()) do
    local basename = vim.fn.fnamemodify(file, ":t")
    local name = vim.fn.fnamemodify(basename, ":r")

    -- Add an entry for every file in the CWD
    table.insert(items, {
      word = "[" .. name,
      label = name,
      insertText = self.mdlink.build_link(name, file),
      filterText = "[" .. name .. "]",
      kind = cmp.lsp.CompletionItemKind.File,
      data = { file = file },
    })
  end

  return items
end

source._heading_canidates = function(self, key)
  local bufname = vim.api.nvim_buf_get_name(0)
  local items = {}

  for _, file in pairs(self.mdlink.list.files()) do
    local basename = vim.fn.fnamemodify(file, ":t")
    local name = vim.fn.fnamemodify(basename, ":r")
    local filetype = vim.filetype.match({ filename = file })

    if filetype == "markdown" and ((key == "" and file == bufname) or (name == key)) then
      local headings = self.mdlink.list.headers(file)

      for _, value in pairs(headings) do
        if key == "" and file == bufname then
          table.insert(items, {
            word = "[#" .. value.key,
            label = "#" .. value.header,
            insertText = self.mdlink.build_link(value.header, nil, value.key),
            filterText = "[#" .. value.key,
            kind = cmp.lsp.CompletionItemKind.Field,
          })
        elseif name == key then
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

  return items
end

return source
