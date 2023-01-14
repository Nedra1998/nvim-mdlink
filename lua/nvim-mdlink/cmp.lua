local source = {}
local mdlink = require("nvim-mdlink")
local cmp = require("cmp")

source.new = function()
  return setmetatable({}, { __index = source })
end

source.is_available = function()
  return vim.bo.filetype == "markdown"
end

source.get_trigger_characters = function()
  return { "[" }
end

source.get_keyword_pattern = function()
  return [=[\%(\s\|^\)\zs\[[^\]]*\]\?]=]
end

-- source.resolve = function(self, item, callback)

-- end

source.execute = function(self, item, callback)
  local pos = vim.fn.getcurpos()
  local line = vim.fn.getline(pos[2])
  if line:sub(pos[3], pos[3]) == "]" then
    vim.fn.setline(pos[2], line:sub(0, pos[3] - 1) .. line:sub(pos[3] + 1))
  end
  callback(item)
end

source.complete = function(self, params, callback)
  local files = mdlink.list_files()

  local bufname = vim.api.nvim_buf_get_name(0)
  local items = {}

  for _, file in pairs(files) do
    local basename = vim.fn.fnamemodify(file, ":t")
    local name = vim.fn.fnamemodify(basename, ":r")
    local ext = vim.fn.fnamemodify(basename, ":e")
    table.insert(items, {
      word = "[" .. name .. "]",
      label = name,
      insertText = "[" .. name .. "](" .. mdlink.relative_path(bufname, file) .. ")",
      filterText = "[" .. name .. "]",
      kind = cmp.lsp.CompletionItemKind.File,
    })

    if ext == "md" then
      local headings = mdlink.list_headings(file)
      if #headings >= 1 then
        local first = headings[1]
        table.insert(items, {
          word = "[" .. first.key .. "]",
          label = first.header,
          insertText = "[" .. first.header .. "](" .. mdlink.relative_path(bufname, file) .. ")",
          filterText = "[" .. first.key .. "]",
          kind = cmp.lsp.CompletionItemKind.File,
        })
      end

      for _, heading in pairs(headings) do
        if file == bufname then
          table.insert(items, {
            word = "[#" .. heading.key .. "]",
            label = "#" .. heading.key,
            insertText = "[" .. heading.header .. "](#" .. heading.key .. ")",
            filterText = "[#" .. heading.key .. "]",
            kind = cmp.lsp.CompletionItemKind.Field,
          })
        end
        table.insert(items, {
          word = "[" .. name .. "#" .. heading.key .. "]",
          label = name .. "#" .. heading.key,
          insertText = "["
            .. heading.header
            .. "]("
            .. mdlink.relative_path(bufname, file)
            .. "#"
            .. heading.key
            .. ")",
          filterText = "[" .. name .. "#" .. heading.key .. "]",
          kind = cmp.lsp.CompletionItemKind.Field,
        })
      end
    end
  end

  callback(items)
end

source._get_documentation = function(_, filename, count)
  local binary = assert(io.open(filename, "rb"))
  local first_kb = binary:read(1024)
  if first_kb:find("\0") then
    return { kind = cmp.lsp.MarkupKind.PlainText, value = "binary file" }
  end

  local contents = {}
  for content in first_kb:gmatch("[^\r\n]+") do
    table.insert(contents, content)
    if count ~= nil and #contents >= count then
      break
    end
  end

  local filetype = vim.filetype.match({ filename = filename })
  if not filetype then
    return { kind = cmp.lsp.MarkupKind.PlainText, value = table.concat(contents, "\n") }
  end

  table.insert(contents, 1, "```" .. filetype)
  table.insert(contents, "```")
  return { kind = cmp.lsp.MarkupKind.Markdown, value = table.concat(contents, "\n") }
end

return source
