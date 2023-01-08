# nvim-mdlink

**nvim-mdlink** provides additional functionality when working with markdown
*links.

## :sparkles: Features

- Follow link under cursor
- Create new link from selected text
- Open links in the default browser
- Open binary files in the system default application

## :zap: Requirements

- [Neovim >= **0.8.0**](https://github.com/neovim/neovim/wiki/Installing-Neovim)

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
})
```

For a complete list of available configuration options see [:help
nvim-mdlink-configuration](https://github.com/Nedra1998/nvim-mdlink/blob/master/doc/nvim-mdlink.txt).

Each option is documented in `:help nvim-mdlink.OPTION_NAME`. Nested options
can be accessed by appending `.`., for example `:help
nvim-mdlink.finder.file`.

## :rocket: Usage

### Keybinding

See [:help nvim-mdlink-mappings](https://github.com/Nedra1998/nvim-mdlink/blob/master/doc/nvim-mdlink.txt).

| Keybinding | Description                                            |
| ---------- | ------------------------------------------------------ |
| `<CR>`     | Follow the link under the cursor, or create a new link |
| `<BS>`     | After following a link, go back to the previous file   |

## :hammer_and_pick: To Do

- [ ] Add Telescope integration
  - [ ] Show all links in current document
  - [ ] Show all backlinks to the current document
- [ ] Add nvim-cmp integration
- [ ] Support visual selection spanning line breaks when creating links
