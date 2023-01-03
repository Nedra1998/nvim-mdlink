local ts_utils = require("nvim-treesitter.ts_utils")
local M = {}

-- TODO: Add option to disabling setting keybindings
-- TODO: Add option to override the file searching
-- TODO: Add option to override the anchor searching
M.config = {}

-- Given a section node, find the heading_content child node
local function get_heading_content(node)
  for child, _ in node:iter_children() do
    if child:type() == "atx_heading" then
      for it, field in child:iter_children() do
        if field == "heading_content" then
          return vim.treesitter.query.get_node_text(it, 0):gsub("^%s*", "")
        end
      end
    elseif child:type() == "setext_heading" then
      for it, field in child:iter_children() do
        if field == "heading_content" then
          return vim.treesitter.query.get_node_text(it, 0):gsub("^%s*", "")
        end
      end
    end
  end
end

-- Recursivly walk the nodes searching for section nodes
local function find_headings(node, headings)
  for child, _ in node:iter_children() do
    if child:type() == "section" then
      headings[get_heading_content(child):lower():gsub("[%p%c]", ""):gsub(" ", "-")] = child
      find_headings(child, headings)
    end
  end
  return headings
end

local function navigate(filename, anchor)
  if filename:len() ~= 0 then
    -- Open the link destination
    local dir = vim.fn.fnamemodify(filename, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
    vim.cmd("edit " .. filename)
  end

  if anchor ~= nil and anchor:len() ~= 0 then
    -- Search for all section headings in the current document
    vim.treesitter.get_parser():parse()
    local headings = {}
    for _, tree in ipairs(vim.treesitter.get_parser():trees()) do
      find_headings(tree:root(), headings)
    end

    -- If the anchor was found jump to that position
    local node = headings[anchor]
    if node ~= nil then
      ts_utils.goto_node(node)
    end
  end
end

M.set_keymap = function()
  local bufnr = vim.fn.bufnr()
  vim.keymap.set("n", "<CR>", function()
    M.follow_or_create_link()
  end, { buffer = bufnr, noremap = true, silent = true, desc = "Follow or create link" })
  vim.keymap.set(
    "v",
    "<CR>",
    [[:lua require'nvim-mdlink'.create_link('v')<CR>]],
    { buffer = bufnr, noremap = true, silent = true, desc = "Create link" }
  )
  vim.keymap.set(
    "n",
    "<BS>",
    [[(&modified == 0 ? ':bdelete<CR>' : ':bprevious<CR>')]],
    { buffer = bufnr, noremap = true, silent = true, expr = true, desc = "Goto previous document" }
  )
end

M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  vim.api.nvim_create_augroup("MDLinkKeymap", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = "MDLinkKeymap",
    pattern = { "markdown" },
    callback = M.set_keymap,
  })
end

M.find_file = function(query)
  return nil
end

M.find_links = function() end

M.find_backlinks = function() end

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
    vim.notify(vim.inspect(vbegin) .. " -- " .. vim.inspect(vend))
    line = vim.fn.getline(vbegin[2])
    lineno = vbegin[2]
    vbegin, vend = vbegin[3], vend[3]
  else
    return false
  end

  -- Find the file to link to
  local file = M.find_file(line:sub(vbegin, vend))
  if file == nil then
    -- If no file was found create new filename
    file = "./" .. line:sub(vbegin, vend):gsub("[%p%c]", ""):gsub("%s", "_"):lower() .. ".md"
  end

  -- Update the line replacing the selected text with the link
  line = line:sub(0, vbegin - 1) .. "[" .. line:sub(vbegin, vend) .. "](" .. file .. ")" .. line:sub(vend + 1)
  vim.fn.setline(lineno, line)

  return true
end

M.follow_link = function()
  -- Use treesitter to parse the current buffer
  vim.treesitter.get_parser():parse()

  -- Find the treesitter inline_link node at the current cursor position
  local pos = vim.fn.getcurpos()
  local link_node = vim.treesitter.get_node_at_pos(pos[1], pos[2] - 1, pos[3], { ignore_injections = false })
  while link_node ~= nil and link_node:type() ~= "inline_link" and link_node:type() ~= "inline" do
    link_node = link_node:parent()
  end

  if link_node == nil or link_node:type() ~= "inline_link" then
    return false
  end

  -- Extract the link text and link destination from the inline link
  local link_destination, anchor_text = nil, nil
  for child, _ in link_node:iter_children() do
    if child:type() == "link_destination" then
      link_destination = vim.treesitter.query.get_node_text(child, pos[1])
    end
  end

  if link_destination == nil then
    return false
  end

  -- Strip the section anchor
  local anchor_start = link_destination:find("#")
  if anchor_start then
    anchor_text = link_destination:sub(anchor_start + 1)
    link_destination = link_destination:sub(1, anchor_start - 1)
  end

  navigate(link_destination, anchor_text)
  return true
end

M.follow_or_create_link = function()
  if not M.follow_link() then
    M.create_link()
  end
end

return M
