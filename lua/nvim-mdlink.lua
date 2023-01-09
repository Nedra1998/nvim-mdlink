local M = {}

M.config = {
  keymap = true,
}

local LINK_STACK = {}
local FILE_CACHE = {}
local HEADER_CACHE = {}

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

local function sanitize_filename(input)
  return input:gsub("[%p%c]", ""):gsub("%s", "_"):lower()
end

local function sanitize_header(input)
  return input:gsub("-", " "):gsub("[%p%c]", ""):gsub("%s", "-"):lower()
end

local function list_files()
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

local function list_headings(input)
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
      headings[sanitize_header(vim.treesitter.get_node_text(node, source):gsub("^%s", ""):gsub("%s$", ""))] = {
        row,
        col,
      }
    end
  end

  HEADER_CACHE[key] = {
    ttl = os.time() + 120,
    data = headings,
  }

  return headings
end

local function system_open(path)
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

M.open = function(path)
  -- If the path is a url then open it with the system launcher
  if path:match("^https?://[%w%.%-]+") then
    return system_open(path)
  end

  -- Otherwise if the path is not an absolute path, or relative to the home
  -- directory, assume it is relative to the current file and resolve the full
  -- path.
  local current_buffer = vim.api.nvim_buf_get_name(0)
  if path:sub(1, 1) ~= "/" and path:sub(1, 1) ~= "~" and path:sub(1, 1) ~= "#" then
    path = vim.fn.fnamemodify(current_buffer, ":h") .. "/" .. path
  end

  -- If the file is a binary file, then use the system launcher
  local file = io.open(path, "rb")
  if file then
    local contents = file:read(1024)
    file:close()
    if contents and contents:match("[^%g%s]") then
      return system_open(path)
    end
  end

  -- Extract the header from the path if it is present
  local filepath, header = path, ""
  local idx = filepath:find("#")
  if idx then
    header = filepath:sub(idx + 1)
    filepath = filepath:sub(1, idx - 1)
  end

  -- If there is a file, then open that file in a new buffer
  if #filepath ~= 0 then
    local dir = vim.fn.fnamemodify(filepath, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end

    vim.cmd("edit " .. filepath)
  end

  local new_buffer = vim.api.nvim_buf_get_name(0)

  -- If there is an header then jump to that header in the current file
  if #header ~= 0 then
    local headings = list_headings(0)
    local header = headings[header]
    if header ~= nil then
      vim.fn.cursor(header[1] + 1, 1)
    end
  end

  -- Push the new file to the LINK_STACK
  if current_buffer ~= new_buffer then
    if #LINK_STACK == 0 or LINK_STACK[#LINK_STACK] ~= current_buffer then
      LINK_STACK = { current_buffer, new_buffer }
    else
      table.insert(LINK_STACK, new_buffer)
    end
  end
end

M.follow_link = function()
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

  -- Open the file
  M.open(dest)
  return true
end

M.create_link = function(mode)
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
    return false
  end

  -- Strip any trailing punctuation for the selected range
  while vbegin ~= vend and line:sub(vbegin, vend):match("%p$") do
    vend = vend - 1
  end

  if vbegin == vend then
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
  local file_query = sanitize_filename(file_input)
  local header_query = sanitize_header(header_input)

  local file, header = nil, nil

  if #file_query ~= 0 then
    -- Search for a matching file in any of the files in the cwd
    local files = list_files()
    local file_query_matcher = file_query:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    for _, filepath in pairs(files) do
      local basename = vim.fn.fnamemodify(filepath, ":p:t:r")
      if basename:match(file_query_matcher) then
        file = filepath
        break
      end
    end

    -- If no match was found then create a new markdown file in the same
    -- directory as the current file.
    if not file then
      file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h") .. "/" .. file_query .. ".md"
    end
  end

  if #header_query ~= 0 then
    local headings = {}
    local header_query_matcher = header_query:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

    -- Get the markdown headings from the selected file
    if not file then
      headings = list_headings(0)
    else
      headings = list_headings(file)
    end

    -- Search the discovered headers for the query string
    for head, _ in pairs(headings) do
      if head:match(header_query_matcher) then
        header = head
        break
      end
    end

    -- If not header matches then just directly use the query string
    if not header then
      header = header_query
    end
  end

  -- Build the new markdown link
  local link = nil
  if file and header then
    link = "[" .. header_input .. "](" .. relative_path(vim.api.nvim_buf_get_name(0), file) .. "#" .. header .. ")"
  elseif header then
    link = "[" .. header_input .. "](#" .. header .. ")"
  elseif file then
    link = "[" .. file_input .. "](" .. relative_path(vim.api.nvim_buf_get_name(0), file) .. ")"
  else
    return false
  end

  -- Update the line in the buffer
  line = line:sub(0, vbegin - 1) .. link .. line:sub(vend + 1)
  vim.fn.setline(lineno, line)

  return true
end

M.follow_or_create_link = function()
  if not M.follow_link() then
    return M.create_link()
  end
  return true
end

M.pop_link = function()
  if #LINK_STACK > 1 and LINK_STACK[#LINK_STACK] == vim.api.nvim_buf_get_name(0) then
    table.remove(LINK_STACK)

    -- Determine if the current buffer should be closed
    local bufnr = vim.fn.bufnr()
    local modified = vim.api.nvim_buf_get_option(bufnr, "modified")
    local in_stack = vim.tbl_contains(LINK_STACK, vim.api.nvim_buf_get_name(bufnr))

    -- Close the current buffer if it is unmodifed and not still in the stack
    if not modified and not in_stack then
      vim.api.nvim_buf_delete(bufnr, {})
    end

    -- Search for the new file in the already open buffers
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if LINK_STACK[#LINK_STACK] == vim.api.nvim_buf_get_name(buffer) then
        vim.api.nvim_set_current_buf(buffer)
        return
      end
    end

    -- If the file was not found open it
    vim.cmd("edit " .. LINK_STACK[#LINK_STACK])
  end
end

local function set_default_keymap()
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
    [[:lua require'.nvim-mdlink'.create_link('v')<CR>]],
    { buffer = bufnr, noremap = true, silent = true, desc = "Create link" }
  )
  vim.keymap.set(
    "n",
    "<BS>",
    M.pop_link,
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
end

return M
