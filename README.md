# nvim-mdlink

**nvim-mdlink** provides additional functionality when working with markdown
links.

## :sparkles: Features

- Follow link under cursor
- Create new link from selected text
- Open links in the default browser
- Open binary files in the system default application
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) markdown link completion integration

## :zap: Requirements

- [Neovim >= **0.8.0**](https://github.com/neovim/neovim/wiki/Installing-Neovim)
- [Treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
  - [markdown](https://github.com/MDeiml/tree-sitter-markdown)
  - [markdown-inline](https://github.com/MDeiml/tree-sitter-markdown)

## :package: Installation

Install with [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'Nedra1998/nvim-mdlink'
```

or with [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use { 'Nedra1998/nvim-mdlink' }
```

or with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ 'Nedra1998/nvim-mdlink' }
```

## :gear: Configuration

```lua
require('nvim-mdlink').setup({
  keymap = true,
  cmp = true
})
```

For a complete list of available configuration options see [:help
nvim-mdlink-configuration](https://github.com/Nedra1998/nvim-mdlink/blob/master/doc/nvim-mdlink.txt).

Each option is documented in `:help nvim-mdlink.OPTION_NAME`.

## :rocket: Usage

### Keybinding

See [:help nvim-mdlink-mappings](https://github.com/Nedra1998/nvim-mdlink/blob/master/doc/nvim-mdlink.txt).

| Keybinding | Description                                            |
| ---------- | ------------------------------------------------------ |
| `<CR>`     | Follow the link under the cursor, or create a new link |
| `<BS>`     | After following a link, go back to the previous file   |

### nvim-cmp Integration


If [nvim-mdlink.cmp](https://github.com/Nedra1998/nvim-mdlink/blob/master/doc/nvim-mdlink.txt)
is `true`, then the `mdlink` completion source will be registered in nvim-cmp is available (i.e. if nvim-cmp has already been loaded by your plugin manager). If nvim-mdlink is loaded before nvim-cmp, then you will need to manually register the completion source in the configuration for nvim-cmp, by using the following snippet.

```lua
local has_mdlink, mdlink = pcall(require, "nvim-mdlink.cmp")
if has_mdlink then
  require('cmp').register_source("mdlink", mdlink.new())
end
```

Then you are able to make use the the mdlink completion source in your nvim-cmp configuration.

```lua
require('cmp').setup {
  sources = {
    { name = 'mdlink' }
  }
}
```