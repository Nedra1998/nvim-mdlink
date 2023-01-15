local M = {}

M.config = {
  keymap = true,
  cmp = false,
}

local STACK = {}
local FILE_CACHE = {}
local HEADER_CACHE = {}

local function sanitize_file(input)
  return input:gsub("[%p%c]", ""):gsub("%s", "_"):lower()
end

local function sanitize_header(input)
  return input:gsub("-", " "):gsub("[%p%c]", ""):gsub("%s", "-"):lower()
end

local function relative_path(from, to)
  local from_path, _ = from:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
  local to_path, to_file = to:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
  if from_path == to_path then
    return to_file
  end

  local from_path_parts, to_path_parts = {}, {}

  for part in from_path:gmatch("[^\\/]+") do
    table.insert(from_path_parts, part)
  end

  for part in to_path:gmatch("[^\\/]+") do
    table.insert(to_path_parts, part)
  end

  for i, part in ipairs(from_path_parts) do
    if part ~= to_path_parts[i] then
      break
    end
    from_path_parts[i] = nil
    to_path_parts[i] = nil
  end

  local out_path = ""
  for _, part in pairs(from_path_parts) do
    if part ~= nil then
      out_path = out_path .. "../"
    end
  end

  for _, part in pairs(to_path_parts) do
    if part ~= nil then
      out_path = out_path .. part .. "/"
    end
  end

  return out_path .. to_file
end

local function select_text(mode)
  mode = mode or vim.fn.mode()

  local line, lineno = nil, nil
  local vbegin, vend = nil, nil

  if mode == "n" then
    -- Find the position of the current WORD
    local pos = vim.fn.getcurpos()
    lineno = pos[2]
    line = vim.fn.getline(lineno)
    local word = vim.fn.expand("<cWORD>"):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

    -- Search for that word in the current line
    repeat
      vbegin, vend = line:find(word, vend or 0)
    until vbegin == nil or vend == nil or (pos[3] >= vbegin and pos[3] <= vend)
  elseif mode == "v" then
    -- Get the start and end position of the selected text. Currently only
    -- supports selecting a single line.
    vbegin, vend = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    lineno = vbegin[2]
    line = vim.fn.getline(lineno)
    vbegin, vend = vbegin[3], vend[3]
  end

  -- If the selected text was not found then exit
  if vbegin == nil or vend == nil then
    return nil, nil, nil, nil
  end

  -- Strip any trailing punctuation for the selected range
  while vbegin ~= vend and line:sub(vbegin, vend):match("%p$") do
    vend = vend - 1
  end

  if vbegin == vend then
    return nil, nil, nil, nil
  end

  return line, lineno, vbegin, vend
end

M.build_link = function(label, file, header)
  if file and header then
    return "[" .. label .. "](" .. relative_path(vim.api.nvim_buf_get_name(0), file) .. "#" .. header .. ")"
  elseif header then
    return "[" .. label .. "](#" .. header .. ")"
  elseif file then
    return "[" .. label .. "](" .. relative_path(vim.api.nvim_buf_get_name(0), file) .. ")"
  end
  return nil
end

M.stack_push = function(previous_file, current_file)
  if previous_file ~= current_file then
    if #STACK == 0 or STACK[#STACK] ~= previous_file then
      STACK = { previous_file, current_file }
    else
      table.insert(STACK, current_file)
    end
  end
end

M.stack_pop = function()
  if #STACK > 1 and STACK[#STACK] == vim.api.nvim_buf_get_name(0) then
    table.remove(STACK)

    -- Determine if the current buffer should be closed
    local bufnr = vim.fn.bufnr()
    local modified = vim.api.nvim_buf_get_option(bufnr, "modified")
    local in_stack = vim.tbl_contains(STACK, vim.api.nvim_buf_get_name(bufnr))

    -- Close the current buffer if it is unmodifed and not still in the stack
    if not modified and not in_stack then
      vim.api.nvim_buf_delete(bufnr, {})
    end

    -- Search for the new file in the already open buffers
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if STACK[#STACK] == vim.api.nvim_buf_get_name(buffer) then
        vim.api.nvim_set_current_buf(buffer)
        return
      end
    end

    -- If the file was not found open it
    vim.cmd("edit " .. STACK[#STACK])
  end
end

M.list = {}

M.list.files = function()
  if FILE_CACHE["ttl"] ~= nil and os.time() < FILE_CACHE["ttl"] then
    return FILE_CACHE["data"]
  end

  local cwd = vim.fn.getcwd()
  local files = {}
  for file in vim.fn.glob("**/*"):gmatch("[^\n]+") do
    file = cwd .. "/" .. file
    if vim.fn.isdirectory(file) == 0 then
      table.insert(files, file)
    end
  end

  FILE_CACHE = {
    ttl = os.time() + 60,
    data = files,
  }

  return files
end

M.list.headers = function(input)
  local MARKDOWN_SECTION_QUERY = [[
    ([
      (atx_heading
        [
          (atx_h1_marker)
          (atx_h2_marker)
          (atx_h3_marker)
          (atx_h4_marker)
          (atx_h5_marker)
          (atx_h6_marker)
        ]
        (inline) @header
      )
      (setext_heading
        (paragraph) @header
        [
          (setext_h1_underline)
          (setext_h2_underline)
        ]
      )
    ])
  ]]

  local tsparser, source, key = nil, nil, nil
  if type(input) == "number" then
    tsparser, source = vim.treesitter.get_parser(input), input
    key = vim.api.nvim_buf_get_name(input)
  else
    key = input
    if HEADER_CACHE[key] ~= nil and os.time() < HEADER_CACHE[key]["ttl"] then
      return HEADER_CACHE[key]["data"]
    end

    local file = io.open(input, "r")
    if file == nil then
      return {}
    end
    local contents = file:read("*a")
    file:close()
    tsparser, source = vim.treesitter.get_string_parser(contents, "markdown"), contents
  end

  -- Parse the treesitter tree for the new buffer
  tsparser:parse()

  -- Parse the query string for markdown
  local query = vim.treesitter.parse_query("markdown", MARKDOWN_SECTION_QUERY)

  local headings = {}
  -- Search the trees for markdown sections
  for _, tree in ipairs(tsparser:trees()) do
    for _, node, _ in query:iter_captures(tree:root(), source) do
      local row, col, _ = node:start()
      local header = vim.treesitter.get_node_text(node, source):gsub("^%s", ""):gsub("%s$", "")
      table.insert(headings, {
        header = header,
        key = sanitize_header(header),
        row = row,
        col = col,
      })
    end
  end

  HEADER_CACHE[key] = {
    ttl = os.time() + 120,
    data = headings,
  }

  return headings
end

M.find = {}

M.find.link = function()
  -- Parse the treesitter tree
  vim.treesitter.get_parser():parse()

  -- Find the inline link under the current cursor position
  local pos = vim.fn.getcurpos()
  local node = vim.treesitter.get_node_at_pos(pos[1], pos[2] - 1, pos[3], { ignore_injections = false })
  while node ~= nil and node:type() ~= "inline_link" and node:type() ~= "inline" do
    node = node:parent()
  end

  -- Exit if we failed to find a link
  if node == nil or node:type() ~= "inline_link" then
    return false
  end

  -- Find the link destination
  local dest = nil
  for child, _ in node:iter_children() do
    if child:type() == "link_destination" then
      dest = vim.treesitter.query.get_node_text(child, pos[1])
      break
    end
  end

  -- Exit if the destination was empty or not found
  if dest == nil or dest:len() == 0 or dest == "#" then
    return true
  end

  return dest
end

M.find.file = function(query)
  query = query:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  for _, file in pairs(M.list.files()) do
    local basename = vim.fn.fnamemodify(file, ":p:t:r")
    if basename:match(query) then
      return file
    end
  end

  return nil
end

M.find.header = function(source, query)
  query = query:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  for _, value in pairs(M.list.headers(source)) do
    if value.key:match(query) then
      return value.key
    end
  end

  return nil
end

M.open = {}

M.open.system = function(path)
  -- Use the system default launcher to open a given file path
  if vim.fn.has("mac") == 1 then
    vim.cmd("silent !open " .. path .. " &")
  elseif vim.fn.has("unix") then
    vim.cmd("silent !xdg-open " .. path .. " &")
  else
    vim.notify("Cannot open path [" .. path .. "] on your operating system.")
    return false
  end
  return true
end

M.open.file = function(file)
  -- If there is a file, then open that file in a new buffer
  if #file == 0 then
    return false
  end
  local dir = vim.fn.fnamemodify(file, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  vim.cmd("edit " .. file)
  return true
end

M.open.header = function(header)
  -- If there is an header then jump to that header in the current file
  if header == nil or #header == 0 then
    return false
  end

  for _, value in pairs(M.list.headers(0)) do
    if value.key == header then
      vim.fn.cursor(value.row + 1, 1)
      return true
    end
  end
  return false
end

M.create = function(mode)
  -- Find currently selected text
  local line, lineno, vbegin, vend = select_text(mode)
  if line == nil then
    return false
  end

  -- Split the header query string from the file query string
  local file_input, header_input = line:sub(vbegin, vend), ""
  local idx = file_input:find("#")
  if idx then
    header_input = file_input:sub(idx + 1)
    file_input = file_input:sub(1, idx - 1)
  end

  -- Sanitize the query strings into the correct format
  local file_query = sanitize_file(file_input)
  local header_query = sanitize_header(header_input)

  local file, header = nil, nil
  local new_file = false

  if #file_query ~= 0 then
    -- Search for a matching file in any of the files in the cwd
    file = M.find.file(file_query)

    -- If no match was found then create a new markdown file in the same
    -- directory as the current file.
    if not file then
      file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h") .. "/" .. file_query .. ".md"
      new_file = true
    end
  end

  if #header_query ~= 0 and new_file == false then
    -- Search for a matching header in the selected file
    header = M.find.header(file or 0, header_query)

    -- If not header matches then just directly use the query string
    if not header then
      header = header_query
    end
  elseif #header_query ~= 0 and new_file == true then
    header = header_query
  end

  -- Build the new markdown link
  local link = nil
  if header then
    link = M.build_link(header_input, file, header)
  else
    link = M.build_link(file_input, file, header)
  end

  if link == nil then
    return false
  end

  -- Update the line in the buffer
  line = line:sub(0, vbegin - 1) .. link .. line:sub(vend + 1)
  vim.fn.setline(lineno, line)

  return true
end

M.follow = function()
  -- Find the current link under the cursor
  local dest = M.find.link()
  if type(dest) ~= "string" then
    return dest
  end

  -- If the path is a url then open it with the system launcher
  if dest:match("^https?://[%w%.%-]+") then
    return M.open.system(dest)
  end

  -- Otherwise if the path is not an absolute path, or relative to the home
  -- directory, assume it is relative to the current file and resolve the full
  -- path.
  local current_buffer = vim.api.nvim_buf_get_name(0)
  if dest:sub(1, 1) ~= "/" and dest:sub(1, 1) ~= "~" and dest:sub(1, 1) ~= "#" then
    dest = vim.fn.fnamemodify(current_buffer, ":h") .. "/" .. dest
  end

  -- If the file is a binary file, then use the system launcher
  local fileio = io.open(dest, "rb")
  if fileio then
    local contents = fileio:read(1024)
    fileio:close()
    if contents and contents:match("[^%g%s]") then
      return M.open.system(dest)
    end
  end

  -- Extract the header from the path if it is present
  local file, header = dest, nil
  local idx = file:find("#")
  if idx then
    header = file:sub(idx + 1)
    file = file:sub(1, idx - 1)
  end

  local previous_file = vim.api.nvim_buf_get_name(0)
  -- Open the file if present in the destination
  M.open.file(file)
  -- Jump to the header if present in the destination
  M.open.header(header)
  -- Push the new file to the link stack
  M.stack_push(previous_file, vim.api.nvim_buf_get_name(0))
  return true
end

M.follow_or_create = function()
  if not M.follow() then
    return M.create()
  end
  return true
end

local function set_default_keymap()
  local bufnr = vim.fn.bufnr()
  vim.keymap.set(
    "n",
    "<CR>",
    M.follow_or_create,
    { buffer = bufnr, noremap = true, silent = true, desc = "Follow or create link" }
  )
  vim.keymap.set(
    "v",
    "<CR>",
    [[:lua require'.nvim-mdlink'.create('v')<CR>]],
    { buffer = bufnr, noremap = true, silent = true, desc = "Create link" }
  )
  vim.keymap.set(
    "n",
    "<BS>",
    M.stack_pop,
    { buffer = bufnr, noremap = true, silent = true, desc = "Goto previous file" }
  )
end

M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  if M.config.keymap == true then
    vim.api.nvim_create_augroup("MDLinkKeymap", { clear = true })
    vim.api.nvim_create_autocmd(
      "FileType",
      { group = "MDLinkKeymap", pattern = { "markdown" }, callback = set_default_keymap }
    )
  end

  if M.config.cmp == true then
    local has_cmp, cmp = pcall(require, "cmp")
    if has_cmp then
      cmp.register_source("mdlink", require("nvim-mdlink.cmp").new())
    end
  end
end

return M
