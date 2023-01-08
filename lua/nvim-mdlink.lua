local ts_utils = require("nvim-treesitter.ts_utils")
local M = {}

M.finder = {}

local function get_abspath_from(from, to)
  local from_path, _ = from:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
  local to_path, to_file = to:match("(.-)([^\\/]-%.?([^%.\\/]*))$")

  if from_path == to_path then
    return to
  end

  local path_parts = {}
  for part in from_path:gmatch("[^\\/]+") do
    table.insert(path_parts, part)
  end

  for part in to_path:gmatch("[^\\/]+") do
    if part == ".." then
      table.remove(path_parts)
    elseif part ~= "." then
      table.insert(path_parts, part)
    end
  end

  return "/" .. table.concat(path_parts, "/") .. "/" .. to_file
end

local function get_relative_path(from, to)
  local from_path, _ = from:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
  local to_path, to_file = to:match("(.-)([^\\/]-%.?([^%.\\/]*))$")

  if from_path == to_path then
    return "./" .. to_file
  end

  local from_path_parts, to_path_parts = {}, {}

  for part in from_path:gmatch("[^\\/]+") do
    table.insert(from_path_parts, part)
  end

  for part in to_path:gmatch("[^\\/]+") do
    table.insert(to_path_parts, part)
  end

  for i, _ in ipairs(from_path_parts) do
    if from_path_parts[i] ~= to_path_parts[i] then
      break
    end
    from_path_parts[i] = nil
    to_path_parts[i] = nil
  end

  local relative_path = ""
  for _, part in pairs(from_path_parts) do
    if part ~= nil then
      relative_path = relative_path .. "../"
    end
  end

  if #relative_path == 0 then
    relative_path = "./"
  end

  for _, part in pairs(to_path_parts) do
    if part ~= nil then
      relative_path = relative_path .. part .. "/"
    end
  end

  return relative_path .. to_file
end

local function open(file)
  if vim.fn.has("mac") == 1 then
    vim.api.nvim_command("silent !open " .. file .. " &")
  elseif vim.fn.has("unix") then
    vim.api.nvim_command("silent !xdg-open " .. file .. " &")
  else
    vim.notify("Cannot open path (" .. file .. ") on your operating system.")
  end
end

local function navigate(file, section)
  if file then
    local dir = vim.fn.fnamemodify(file, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end

    vim.cmd("edit " .. file)
  end

  if section then
    local function find_node_by_field(node, field_name)
      local nodes = {}

      for child, field in node:iter_children() do
        if field == field_name then
          table.insert(nodes, child)
        end

        local child_nodes = find_node_by_field(child, field_name)
        for _, child_node in ipairs(child_nodes) do
          table.insert(nodes, child_node)
        end
      end
      return nodes
    end

    vim.treesitter.get_parser():parse()
    for _, tree in ipairs(vim.treesitter.get_parser():trees()) do
      local sections = find_node_by_field(tree:root(), "heading_content")

      for _, node in ipairs(sections) do
        local anchor = vim.treesitter.query
          .get_node_text(node, 0)
          :gsub("^%s*", "")
          :gsub("%s*$", "")
          :gsub("[%p%c]", "")
          :gsub(" ", "-")
          :lower()

        if anchor == section then
          ts_utils.goto_node(node)
          return
        end
      end
    end
  end
end

M.finder.file = function(query)
  query = query:gsub("[%p%c]", ""):gsub("%s", "_"):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):lower()
  local cwd = vim.fn.getcwd()
  local files = {}
  for file in vim.fn.glob("**/*"):gmatch("[^\n]+") do
    if file:gsub("[%p%c]", ""):gsub("%s", "_"):lower():find(query) then
      if vim.fn.isdirectory(cwd .. "/" .. file) == 0 then
        table.insert(files, cwd .. "/" .. file)
      end
    end
  end

  return files
end

M.finder.section = function(file, query)
  if file:sub(-3) ~= ".md" then
    return {}
  end
  query = query:gsub("[%p%c]", ""):gsub("%s", "-"):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):lower()
  local file_contents = vim.fn.readfile(file)
  local sections = {}

  for _, line in ipairs(file_contents) do
    local heading = line:match("^#+%s+(.+)")
    if heading and heading:gsub("[%p%c%s]", ""):lower():find(query) then
      table.insert(sections, heading)
    end
  end

  return sections
end

M.config = {
  keymap = true,
  finder = {
    file = M.finder.file,
    section = M.finder.section,
  },
}

M.link_stack = {}

M.create_link = function(mode)
  mode = mode or vim.fn.mode()
  local vbegin, vend = nil, nil
  local line, lineno = nil, nil

  if mode == "n" then
    -- Find the position of the current word
    local pos = vim.fn.getcurpos()
    lineno = pos[2]
    line = vim.fn.getline(lineno)
    local select = vim.fn.expand("<cword>")
    vend = 0

    -- Find the position of that word in the current line
    repeat
      vbegin, vend = line:find(select, vend)
    until vbegin == nil or vend == nil or (pos[3] >= vbegin and pos[3] <= vend)
    if vbegin == nil or vend == nil then
      return false
    end
  elseif mode == "v" then
    -- Get the position of the start and end of the selected text
    -- TODO: This currently only works for text on a single line
    vbegin, vend = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    line = vim.fn.getline(vbegin[2])
    lineno = vbegin[2]
    vbegin, vend = vbegin[3], vend[3]
  else
    return false
  end

  local file_query, section_query = line:sub(vbegin, vend), nil
  local idx = file_query:find("#")
  if idx then
    section_query = file_query:sub(idx + 1)
    file_query = file_query:sub(1, idx - 1)

    if file_query:len() == 0 then
      file_query = nil
    end
  end

  local file, section = nil, nil

  if file_query then
    local files = M.finder.file(file_query)
    if #files == 0 then
      file = vim.fn.getcwd() .. "/" .. file_query:gsub("[%p%c]", ""):gsub("%s", "_"):lower() .. ".md"
    else
      file = files[1]
    end
  end

  if section_query then
    local sections = M.finder.section(file or vim.api.nvim_buf_get_name(0), section_query)
    if #sections ~= 0 then
      section = sections[1]
    end
  end

  if file and section then
    line = line:sub(0, vbegin - 1)
      .. "["
      .. file_query
      .. " "
      .. section_query
      .. "]("
      .. get_relative_path(vim.api.nvim_buf_get_name(0), file)
      .. "#"
      .. section:gsub("[%p%c]", ""):gsub(" ", "-"):lower()
      .. ")"
      .. line:sub(vend + 1)
  elseif file and not section then
    line = line:sub(0, vbegin - 1)
      .. "["
      .. file_query
      .. "]("
      .. get_relative_path(vim.api.nvim_buf_get_name(0), file)
      .. ")"
      .. line:sub(vend + 1)
  elseif not file and section then
    line = line:sub(0, vbegin - 1)
      .. "["
      .. section_query
      .. "](#"
      .. section:gsub("[%p%c]", ""):gsub(" ", "-"):lower()
      .. ")"
      .. line:sub(vend + 1)
  else
    return false
  end
  vim.fn.setline(lineno, line)

  return true
end

M.follow_link = function()
  vim.treesitter.get_parser():parse()

  local pos = vim.fn.getcurpos()
  local node = vim.treesitter.get_node_at_pos(pos[1], pos[2] - 1, pos[3], { ignore_injections = false })
  while node ~= nil and node:type() ~= "inline_link" and node:type() ~= "inline" do
    node = node:parent()
  end

  if not node or node:type() ~= "inline_link" then
    return false
  end

  local destination = nil
  for child, _ in node:iter_children() do
    if child:type() == "link_destination" then
      destination = vim.treesitter.query.get_node_text(child, pos[1])
    end
  end

  if destination == nil or destination:len() == 0 then
    return false
  end

  -- If the link is a url use the system launcher
  if destination:match("^https?://[%w%.%-]+") then
    open(destination)
    return true
  end

  -- Readh the chunk of the file to see if it is binary
  local file = io.open(destination, "rb")
  if file then
    local contents = file:read(1024)
    if contents and contents:match("[^%g%s]") then
      open(destination)
      return true
    end
  end

  local idx = destination:find("#")
  local section = nil
  if idx then
    section = destination:sub(idx + 1)
    destination = destination:sub(1, idx - 1)
    if destination:len() == 0 then
      destination = nil
    end
  end

  if destination and destination:len() ~= 0 then
    destination = get_abspath_from(vim.api.nvim_buf_get_name(0), destination)
  end

  local current_buf = vim.api.nvim_buf_get_name(0)
  navigate(destination, section)
  local new_buf = vim.api.nvim_buf_get_name(0)

  if destination then
    if #M.link_stack == 0 or M.link_stack[#M.link_stack] ~= current_buf then
      M.link_stack = { current_buf, new_buf }
    else
      table.insert(M.link_stack, new_buf)
    end
  end

  return true
end

M.pop_link = function()
  if #M.link_stack > 1 and M.link_stack[#M.link_stack] == vim.api.nvim_buf_get_name(0) then
    table.remove(M.link_stack)

    local bufnr = vim.fn.bufnr()
    if not vim.api.nvim_buf_get_option(bufnr, "modified") then
      local name = vim.api.nvim_buf_get_name(bufnr)
      local in_stack = false
      for _, value in ipairs(M.link_stack) do
        if value == name then
          in_stack = true
          break
        end
      end

      if not in_stack then
        vim.api.nvim_buf_delete(bufnr, {})
      end
    end

    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buffer) == M.link_stack[#M.link_stack] then
        vim.api.nvim_set_current_buf(buffer)
        break
      end
    end
  end
end

M.follow_or_create_link = function()
  if not M.follow_link() then
    M.create_link()
  end
end

M.set_keymap = function()
  local bufnr = vim.fn.bufnr()
  vim.keymap.set(
    "n",
    "<CR>",
    M.follow_or_create_link,
    { buffer = bufnr, noremap = true, silent = true, desc = "Follow or create link" }
  )
  vim.keymap.set(
    "v",
    "<CR>",
    [[:lua require'nvim-mdlink'.create_link('v')<CR>]],
    { buffer = bufnr, noremap = true, silent = true, desc = "Create link" }
  )
  vim.keymap.set(
    "n",
    "<BS>",
    M.pop_link,
    { buffer = bufnr, noremap = true, silent = true, desc = "Goto previous document" }
  )
end

M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  if M.config.keymap then
    vim.api.nvim_create_augroup("MDLinkKeymap", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = "MDLinkKeymap",
      pattern = { "markdown" },
      callback = M.set_keymap,
    })
  end
end

return M
