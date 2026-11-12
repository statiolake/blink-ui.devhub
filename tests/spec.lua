-- nvim --headless --clean --cmd 'set rtp^=.' --cmd 'set rtp^=../devhub.nvim' -l tests/spec.lua
-- (tests/run.sh): the tree, and the plugin over a stand-in blink.cmp and a
-- stand-in DevHub (devhub.nvim's real component builders). Leaves Neovim
-- with an error on failure.
local failures = {}
local function check(ok, what)
  if not ok then
    table.insert(failures, what)
  end
end
local function flush()
  vim.wait(50, function()
    return false
  end)
end

local ui = require('devhub.ui')

-- 1. The tree, pure.
local tree = require 'blink-ui.tree'
check(tree.window(1, 1, 16, 10, 2) == 1, 'the window stays at the top')
check(tree.window(1, 9, 16, 10, 2) == 2, 'two rows kept below the selection')
check(tree.window(5, 6, 16, 10, 2) == 4, 'two rows kept above it')
check(tree.window(1, 16, 16, 10, 2) == 7, 'the last row at the bottom')
check(tree.window(7, nil, 3, 10, 2) == 1, 'a short list from its top')
local runs = tree.label_runs('useState', { 0, 1, 2, 4 })
check(vim.deep_equal(vim.tbl_map(function(r) return r.text end, runs), { 'use', 'S', 't', 'ate' }), 'label runs')
check(runs[1].hl == 'BlinkCmpLabelMatch' and runs[2].hl == 'BlinkCmpLabel' and runs[1].mono, 'matches in their group')
local wide = tree.label_runs('äb', { 0 })
check(#wide == 2 and wide[1].text == 'ä', 'a match is a whole character')
check(tree.label_runs('x', {}, true)[1].hl == 'BlinkCmpLabelDeprecated', 'deprecated')
local atom = {
  columns = { { 'kind_icon' }, { 'label', gap = 1 }, { 'kind' } },
  components = {
    kind_icon = { text = function(ctx) return ' ' .. ctx.kind_icon .. ' ' end },
    kind = {
      text = function(ctx)
        local detail = ctx.item.detail or ''
        if detail ~= '' and #detail <= 16 then return detail end
        return ctx.kind:lower()
      end,
      highlight = 'BlinkCmpLabelDescription',
    },
  },
}
local cols = tree.columns(atom)
check(cols.badge and cols.label and vim.deep_equal(cols.right, { 'kind' }), 'the person\'s columns')
local by_mode = tree.columns({ columns = function(c) return c.cmd and { { 'label' } } or atom.columns end }, {})
check(by_mode.badge and by_mode.right[1] == 'kind', 'columns as a function of the context')
local function ctx(label, kind, detail)
  return { label = label, label_detail = '', kind = kind, kind_icon = kind:sub(1, 1):lower(), kind_hl = 'BlinkCmpKind' .. kind,
    label_matched_indices = { 0, 1 }, item = { label = label, detail = detail } }
end
local row = tree.row(ui, ctx('user', 'Variable', 'User'), atom, cols, true)
check(row.type == 'hstack' and #row.children == 3, 'a row: badge, label, right')
check(row.children[1].type == 'badge' and row.children[1].text == 'v' and row.children[1].size == 'sm'
  and row.children[1].hl == 'BlinkCmpKindVariable', 'the kind\'s small badge in its group')
check(row.children[2].anchor == true and row.children[2].grow == true, 'the label: anchored, taking the room')
check(row.children[3].runs[1].text == 'User' and row.children[3].size == 'sm', 'the right column: the person\'s text')
local node, rel = tree.build(ui, { ctxs = { ctx('a', 'Text'), ctx('b', 'Text') }, draw = atom, cols = cols, top = 3,
  count = 9, selected = 4, doc = tree.doc(ui, { documentation = { kind = 'markdown', value = '**hi**' } }) })
local list = node.children[1]
check(rel == 2 and list.selected == 2 and list.band == 'BlinkCmpMenuSelection', 'the band on the selected row in sight')
check(node.children[2].children[1].text == '3–4 / 9', 'where the rows are in the list')
-- the text as far in across as down: the rows', the count's and the pane's pad
check(list.children[1].pad[2] == tree.INSET and node.children[2].pad[2] == tree.INSET
  and node.children[3].pad[1] == tree.INSET and node.children[3].pad[2] == tree.INSET, 'one inset across and down')
check(node.children[3].pane == 'doc' and node.children[3].children[1].type == 'markdown', 'the documentation in a pane')
local bare = tree.build(ui, { ctxs = { ctx('a', 'Text') }, draw = atom, cols = cols, top = 1, count = 1 })
check(#bare.children == 2 and #bare.children[2].children == 0, 'no documentation: an empty pane')
check(list.children[2].children[2].anchor == nil, 'one anchored label')
check(ui.validate(node), 'the tree validates')
check(tree.doc(ui, { detail = 'string' }, 'string') == nil, 'a detail the right column shows is not said twice')
local d = tree.doc(ui, { detail = '(a) => b', documentation = 'plain' }, 'function', 'typescript')
check(d and d[1].text == '```typescript\n(a) => b\n```' and d[2].type == 'markdown', 'a long detail as code')
check(tree.doc(ui, { documentation = { kind = 'plaintext', value = 'x' } })[1].type == 'text', 'plain text as text')
-- the command line's kinds: what is completed, for blink's cmdline source
local icons = { Keyword = 'k', Property = 'p', File = 'f', Folder = 'd', Color = 'c' }
local function cctx(label, source)
  return { label = label, kind = 'Property', kind_icon = 'p', kind_hl = 'BlinkCmpKindProperty',
    source_id = source or 'cmdline', item = { label = label } }
end
local k = tree.cmdline_kind(cctx 'restart', 'command', icons)
check(k.kind == 'Keyword' and k.kind_icon == 'k' and k.kind_hl == 'BlinkCmpKindKeyword' and k.label == 'restart',
  'a command: a keyword')
check(tree.cmdline_kind(cctx 'foldcolumn', 'option', icons).kind_icon == 'p', 'an option: a property')
check(tree.cmdline_kind(cctx 'lua/', 'file', icons).kind == 'Folder', 'a directory: a folder')
check(tree.cmdline_kind(cctx 'init.lua', 'file', icons).kind == 'File', 'a file')
check(tree.cmdline_kind(cctx 'Normal', 'highlight', icons).kind_icon == 'c', 'a highlight group: a colour')
local path = cctx('lua/', 'path')
path.kind = 'Folder'
check(tree.cmdline_kind(path, 'file', icons) == path, 'another source\'s kind as blink gives it')
check(tree.cmdline_kind(cctx 'x', 'custom,Foo', icons).kind == 'Property', 'an unknown completion: blink\'s kind')

-- 2. The plugin, over stand-ins.
local K = { 'Text', 'Method', 'Function' }
local items = {}
for i = 1, 14 do
  items[i] = { label = 'item' .. i, kind = (i % 3) + 1, detail = 'T' .. i,
    documentation = i % 2 == 0 and { kind = 'markdown', value = 'doc ' .. i } or nil }
end
local selected
local menu_buf = vim.api.nvim_create_buf(false, true)
local docs_buf = vim.api.nvim_create_buf(false, true)
local scrolled = {}
local blink_menu = { win = { buf = menu_buf } }
local blink_docs = { win = { buf = docs_buf } }
function blink_docs.scroll_up(n) table.insert(scrolled, -n) end
function blink_docs.scroll_down(n) table.insert(scrolled, n) end
package.loaded['blink.cmp'] = {
  get_items = function() return items end,
  get_context = function() return { cursor = { 1, 3 }, bounds = { start_col = 1 } } end,
  get_selected_item_idx = function() return selected end,
  is_menu_visible = function() return true end,
}
package.loaded['blink.cmp.config'] = { completion = { menu = { max_height = 10, min_width = 36, draw = atom },
  documentation = { window = { max_width = 36 } } } }
package.loaded['blink.cmp.completion.windows.menu'] = blink_menu
package.loaded['blink.cmp.completion.windows.documentation'] = blink_docs
local resolves = 0
package.loaded['blink.cmp.sources.lib'] = { resolve = function(_, item)
  resolves = resolves + 1
  return { map = function(_, fn) fn(item) end }
end }
local contexts = 0
package.loaded['blink.cmp.completion.windows.render.context'] = { get_from_items = function(_, _, list)
  contexts = contexts + #list
  return vim.tbl_map(function(item)
    return { label = item.label, label_detail = '', kind = K[item.kind], kind_icon = K[item.kind]:sub(1, 1),
      kind_hl = 'BlinkCmpKind' .. K[item.kind], label_matched_indices = {}, item = item, source_id = item.source_id }
  end, list)
end }

local sent = { popups = {}, updates = 0, selects = {}, scrolls = {}, panes = {} }
local function fake_popup(opts)
  local p = { opts = opts, open = true, component = opts.component }
  table.insert(sent.popups, p)
  local h = {}
  function h:is_open() return p.open end
  function h:close() p.open = false end
  function h:update(c) sent.updates = sent.updates + 1; p.component = c end
  function h:select(n) table.insert(sent.selects, n) end
  function h:pane(name, children) table.insert(sent.panes, { name, children }) end
  function h:scroll(by, pane) table.insert(sent.scrolls, { by, pane }) end
  return h
end
package.loaded['devhub'] = { gui = { available = function() return true end, ui = ui, popup = fake_popup,
  has_cmdline_popup = function() return true end } }

local plugin = require 'blink-ui'
local mode = 'insert'
plugin._mode = function() return mode end
plugin.setup {}
local function blink_event(name)
  vim.api.nvim_exec_autocmds('User', { pattern = name })
  flush()
end

-- blink's windows hidden as they open
local menu_win = vim.api.nvim_open_win(menu_buf, false, { relative = 'editor', row = 1, col = 1, width = 10, height = 3 })
check(vim.api.nvim_win_get_config(menu_win).hide == true, 'blink\'s menu window hidden as it opens')

blink_event 'BlinkCmpMenuOpen'
local pop = sent.popups[1]
check(pop and pop.opts.min_width == 44 and pop.opts.max_width == 44, 'one width, with or without documentation')
check(pop and vim.deep_equal(pop.opts.close_on, {}) and pop.opts.anchor.col == 0, 'anchored where the word starts')
check(pop and #pop.component.children[1].children == 10, 'only the rows in sight')
check(contexts == 10, 'draw contexts for the rows in sight only')

-- a selection: its index alone; the documentation that comes is content
selected = 1
blink_event 'BlinkCmpListSelect'
check(#sent.popups == 1, 'the same popup')
check(sent.selects[1] == 1, 'the selection sent as its index')
local before = sent.updates
selected = 2
blink_event 'BlinkCmpListSelect'
check(sent.selects[2] == 2, 'the next selection, its index')
check(sent.updates == before, 'no tree for a selection that stays in sight')
local pane = sent.panes[#sent.panes]
check(pane and pane[1] == 'doc' and pane[2][1].text == 'doc 2', 'its documentation, the pane alone: ' .. vim.inspect(sent.panes))
check(pane and #pane[2] == 1, 'its detail is in the right column, not here')
selected = 3
blink_event 'BlinkCmpListSelect'
check(#sent.panes[#sent.panes][2] == 0, 'an item with no documentation: the pane emptied')

-- scroll_documentation_*: the pane
selected = 2
blink_event 'BlinkCmpListSelect'
blink_docs.scroll_down(4)
blink_docs.scroll_up(2)
check(vim.deep_equal(sent.scrolls, { { 4, 'doc' }, { -2, 'doc' } }), 'blink\'s documentation scroll is the pane\'s')
check(#scrolled == 0, 'not blink\'s hidden window: ' .. vim.inspect(scrolled))

-- past the rows in sight: the tree again, the rows moved
local updates = sent.updates
selected = 9
blink_event 'BlinkCmpListSelect'
check(sent.updates > updates, 'the rows scrolled: a new tree')
check(pop.component.children[2].children[1].text == '2–11 / 14', 'rows 2–11 in sight')

-- closed with blink's menu
blink_event 'BlinkCmpMenuClose'
check(not pop.open, 'closed with blink\'s menu')
blink_docs.scroll_down(1)
check(scrolled[#scrolled] == 1, 'with no popup, blink scrolls its own')

-- The command line: the same popup on DevHub's box, the person's cmdline
-- columns with the kind's badge in front.
local insert_items = items
items = {}
for i, label in ipairs { 'restart', 'registers', 'redrawstatus' } do
  items[i] = { label = label, kind = 1, source_id = 'cmdline' }
end
K[1] = 'Property'
local cmd_cols = { { 'pad', 'label' } }
package.loaded['blink.cmp.config'].completion.menu.draw = vim.tbl_extend('force', atom, {
  columns = function() return mode == 'cmdline' and cmd_cols or atom.columns end,
})
package.loaded['blink.cmp.config'].appearance = { kind_icons = { Keyword = 'k', Property = 'p' } }
package.loaded['blink.cmp'].get_context = function() return { cursor = { 1, 4 }, bounds = { start_col = 1 } } end
local getcmdcompltype = vim.fn.getcmdcompltype
vim.fn.getcmdcompltype = function() return 'command' end
mode = 'cmdline'
selected = nil
vim.api.nvim_exec_autocmds('CmdlineEnter', {})
local before_cmd = #sent.popups
blink_event 'BlinkCmpMenuOpen'
local cpop = sent.popups[#sent.popups]
check(#sent.popups == before_cmd + 1, 'one popup for the command line')
check(cpop ~= pop and cpop.open, 'a popup of its own')
check(cpop.opts.anchor.cmdline == 0 and cpop.opts.anchor.buf == nil, 'on the command line, where the word starts')
check(cpop.opts.placement == nil, 'DevHub\'s side for it: above the box')
local crow = cpop.component.children[1].children[1]
check(crow.children[1].type == 'badge' and crow.children[1].text == 'k' and crow.children[1].hl == 'BlinkCmpKindKeyword',
  'the badge in front, saying a command: ' .. vim.inspect(crow.children[1]))
check(crow.children[2].runs[1].text == 'restart' and #crow.children == 2, 'the label; the pad column says nothing')
selected = 2
blink_event 'BlinkCmpListSelect'
check(sent.selects[#sent.selects] == 2 and #sent.popups == before_cmd + 1, 'a selection: its index')
vim.api.nvim_exec_autocmds('CmdlineLeave', {})
check(not cpop.open, 'closed with the command line')
vim.fn.getcmdcompltype = getcmdcompltype
items = insert_items
K[1] = 'Text'
mode = 'insert'

-- blink's internals moved: blink's float, the person told once
local notified = {}
local notify = vim.notify
vim.notify = function(msg) table.insert(notified, msg) end
package.loaded['blink.cmp.completion.windows.render.context'] = { get_from_items = function() error 'moved' end }
selected = 1
blink_event 'BlinkCmpMenuOpen'
check(#notified == 1 and notified[1]:find('blink.cmp draws its own menu', 1, true), 'told once')
check(not plugin.active(), 'inactive after a failure')
check(vim.api.nvim_win_get_config(menu_win).hide == false, 'blink\'s window shown again')
vim.notify = notify

-- off: blink's
plugin.setup {}
vim.g.blink_ui_devhub = false
check(not plugin.active(), 'vim.g.blink_ui_devhub = false: blink\'s')
vim.g.blink_ui_devhub = nil
plugin.setup { enabled = false }
check(not plugin.active(), 'enabled = false: blink\'s')

if #failures > 0 then
  io.stderr:write('FAIL\n  ' .. table.concat(failures, '\n  ') .. '\n')
  os.exit(1)
end
print 'blink-ui: ok'
