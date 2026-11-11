# blink-ui.devhub

[blink.cmp](https://github.com/Saghen/blink.cmp)'s insert-mode completion
menu, drawn by [DevHub](https://github.com/statiolake/devhub): the menu and
the selected item's documentation in one popup at the cursor — your own
columns in DevHub's type (the kind as a small rounded badge in your
`BlinkCmpKind*` colours, the label with its matched letters, the rest truly
right-aligned), a band behind the selected row that glides from row to row,
the documentation as markdown with coloured code, the list's words lined up
under the word you type, one width with or without documentation.

A DevHub extension (named `.devhub`, as Neovim plugins are `.nvim`): DevHub's
GUI is its engine, so it needs DevHub and devhub.nvim and is meant to be
loaded only there (the `cond` below); a terminal Neovim keeps blink's own
menu by not loading it.

## What stays blink's

Everything but the drawing. Sources, fuzzy matching, sorting, selection, the
preview it inserts, accepting, and your keys: `select_next`, `accept`,
`hide`, `scroll_documentation_up`/`_down` and every mapping built on
`is_visible()` work as ever, because blink's own menu and documentation
windows still open — hidden (`hide = true`) as they open, never drawn.
`scroll_documentation_*` scroll the popup's documentation. The command
line's menu stays blink's float.

blink's internals this reads, each behind `pcall`: its windows' buffers (to
hide them) and the documentation window's `scroll_up`/`scroll_down`,
`render.context.get_from_items` (the context blink gives its own draw
components: matched letters, kind icon and group) and `sources.lib.resolve`
(the documentation, as blink caches it). When they are not what it expects
(another blink), or anything fails, blink draws its own float and you are
told once.

## Install

Needs blink.cmp and [devhub.nvim](https://github.com/statiolake/devhub.nvim).

```lua
{
  'statiolake/blink-ui.devhub',
  cond = vim.env.DEVHUB_NEOVIM_GUI == '1',   -- only in DevHub's GUI
  dependencies = { 'saghen/blink.cmp', 'statiolake/devhub.nvim' },
  event = 'InsertEnter',
  main = 'blink-ui',
  opts = {},
}
```

## Options

```lua
require('blink-ui').setup {
  enabled = true,         -- false: blink draws its own menu
  width = nil,            -- cells, the same with or without documentation;
                          -- nil: blink's menu min_width or documentation max_width, at least 44
  doc_max_height = 240,   -- the documentation's height in pixels; taller scrolls
}
```

`vim.g.blink_ui_devhub = true | false` turns it on or off while Neovim runs.

The rows are your `completion.menu.draw.columns`: `kind_icon` is the badge,
`label` the label, every other component (`kind`, `label_description`,
`source_name`, …) is in the right column, each with its own `text` and
`highlight` functions. The menu is `completion.menu.max_height` rows; the
band is `BlinkCmpMenuSelection`'s ground. An item's `detail` is shown above
its documentation unless the right column already shows it.

## Cost

Only the rows in sight are drawn. A selection that stays in sight sends its
index alone, and the documentation that comes with it is the pane's content
alone; the tree is sent again only when the rows change (typing, scrolling
past the rows in sight). Measured in DevHub: about 4 KB per typed key, about
0.9 KB per selection move, 1–3 ms of Lua.

## Tests

```sh
NVIM=nvim DEVHUB_NVIM=../devhub.nvim tests/run.sh
```
