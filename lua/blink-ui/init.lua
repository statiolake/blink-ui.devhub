-- blink-ui.devhub: blink.cmp's completion menu and the selected item's
-- documentation, drawn by DevHub as one popup: at the cursor in insert
-- mode, on DevHub's command-line box on the command line.
--
-- blink keeps everything but the drawing: sources, matching, sorting,
-- selection, the preview it inserts, accepting, and the person's keys. Its
-- own menu and documentation windows still open — so `is_visible()`,
-- `select_next()` and every key built on them behave as ever — and are
-- hidden (`hide = true`) in the same tick they open, never drawn. DevHub
-- draws a devhub.nvim `gui.popup` instead: rows of the person's own columns
-- (the kind's badge, the label with its matched letters, the rest at the
-- right), a band behind the selected row that glides, the documentation as
-- markdown in a pane under the list that blink's scroll_documentation_*
-- scroll. A row clicked is selected, a row double-clicked accepted. On
-- the command line the same popup stands on DevHub's own
-- command-line box (gui.popup's anchor = 'cmdline'), above it, its words
-- over the word typed; its rows are the person's cmdline columns with the
-- kind's badge in front, as in insert mode, the badge saying what the
-- command line completes (tree.cmdline_kind). A DevHub that cannot put a
-- popup there leaves blink's float on the command line.
--
-- A DevHub extension: it needs DevHub's GUI and devhub.nvim and is loaded
-- only there. When blink's internals are not what it expects (another
-- blink), or anything here fails, blink draws its own float.

local blink = require 'blink-ui.blink'
local tree = require 'blink-ui.tree'

local M = {}

---@class blink_ui.Config
local defaults = {
  -- false: blink draws its own menu. vim.g.blink_ui_devhub (true / false)
  -- overrides it while Neovim runs.
  enabled = true,
  -- The popup's width in cells, the same with or without documentation;
  -- nil: blink's menu min_width or documentation max_width, at least 44.
  width = nil,
  -- The documentation pane's height in pixels; taller scrolls inside.
  doc_max_height = 240,
}

M.config = vim.deepcopy(defaults)

-- Per menu: the popup, its anchor, the first row in sight, what the tree
-- sent shows (to tell a selection move from a content change), the
-- documentation resolved per item.
local state = {}
local function reset()
  if state.popup and state.popup:is_open() then
    state.popup:close()
  end
  state = { top = 1, docs = setmetatable({}, { __mode = 'k' }) }
end
reset()

-- Counters for measuring: trees, selections and panes sent, Lua time.
M.stats = { trees = 0, selects = 0, panes = 0, ms = 0, max_ms = 0 }

local broken = false

--- Whether the menu is DevHub's now: enabled, in DevHub's GUI, blink as
--- expected, nothing failed.
function M.active()
  local g = vim.g.blink_ui_devhub
  if g == false or (g == nil and M.config.enabled == false) or broken then
    return false
  end
  local ok, devhub = pcall(require, 'devhub')
  return ok and devhub.gui ~= nil and devhub.gui.available() == true
end

-- Which menu blink shows now: 'insert' (or Select mode), 'cmdline' (when
-- this DevHub puts popups on its command line), or nil (blink's own).
function M._mode()
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  if mode == 'i' or mode == 's' then
    return 'insert'
  end
  if mode == 'c' and vim.fn.getcmdtype() ~= '' then
    local gui = require('devhub').gui
    return gui.has_cmdline_popup and gui.has_cmdline_popup() and 'cmdline' or nil
  end
  return nil
end
local function menu_mode()
  return M._mode()
end

--- Something here or in blink's internals failed: blink's own float from
--- now on (and the person told once).
local function fall_back(err)
  if broken then
    return
  end
  broken = true
  reset()
  pcall(blink.hide, false)
  pcall(blink.route_doc_scroll, nil)
  vim.notify('blink-ui.devhub: blink.cmp draws its own menu (' .. tostring(err) .. ')', vim.log.levels.WARN)
end

local function width(config)
  if M.config.width then
    return M.config.width
  end
  local c = config.completion
  return math.max(c.menu.min_width or 0, c.documentation.window.max_width or 0, 44)
end

-- Which item's documentation to show: the selected one's once blink
-- resolved it; until then the one shown stays, as blink's own window keeps
-- it. Answers the list item (its resolved form is state.docs[item]) or false.
local function doc_source(item, context)
  if not item then
    return false
  end
  if state.docs[item] ~= nil then
    return item
  end
  if state.resolving ~= item then
    state.resolving = item
    blink.resolve(context, item, function(resolved)
      state.docs[item] = resolved
      M.schedule()
    end)
  end
  return state.doc_src or false
end

-- The documentation of src (a list item blink resolved) as nodes, its
-- detail left out when the right column already shows it.
local function doc_nodes(items, top, rows, context, src, filetype, ctxs)
  local i
  for j = top, math.min(#items, top + rows - 1) do
    if items[j] == src then
      i = j
    end
  end
  local shown
  if i then
    local ctx = ctxs and ctxs[i - top + 1] or blink.contexts(context, { src })[1]
    local draw = blink.config().completion.menu.draw
    for _, name in ipairs(tree.columns(draw, context).right) do
      shown = shown or tree.component(draw, name, ctx)
    end
  end
  return tree.doc(require('devhub').gui.ui, state.docs[src], shown and vim.trim(shown), filetype)
end

local function render()
  state.pending = false
  local t0 = vim.uv.hrtime()
  local cmp = blink.cmp()
  local mode = M.active() and menu_mode()
  if not cmp or not mode then
    return
  end
  local items = cmp.get_items()
  local context = cmp.get_context()
  if not context or type(items) ~= 'table' or #items == 0 or not cmp.is_menu_visible() then
    if state.popup then
      reset()
    end
    return
  end
  blink.hide(true)
  local config = blink.config()
  local rows = config.completion.menu.max_height or 10
  local selected = cmp.get_selected_item_idx()
  local top = tree.window(state.items == items and state.top or 1, selected, #items, rows, 2)
  local src = doc_source(selected and items[selected], context)
  local buf = vim.api.nvim_get_current_buf()
  local cmdline = mode == 'cmdline'
  local filetype = cmdline and 'vim' or vim.bo[buf].filetype
  -- The word's start: in the buffer, or in the command line's text.
  local anchor = cmdline and { cmdline = context.bounds.start_col - 1 }
    or { buf = buf, lnum = context.cursor[1], col = context.bounds.start_col - 1 }
  local key = cmdline and 'cmdline:' .. anchor.cmdline or table.concat({ buf, anchor.lnum, anchor.col }, ':')
  if state.popup and (state.anchor ~= key or not state.popup:is_open()) then
    state.popup:close()
    state.popup = nil
  end
  -- The same rows: the selection moved (its index alone) and perhaps the
  -- documentation (the pane alone).
  local cheap = state.popup and state.popup.select and state.popup.pane
  if cheap and state.items == items and state.top == top and state.count == #items then
    local rel = selected and selected - top + 1 or 0
    if rel ~= state.rel then
      state.popup:select(rel)
      state.rel = rel
      M.stats.selects = M.stats.selects + 1
    end
    if state.doc_src ~= src then
      local doc = src and doc_nodes(items, top, rows, context, src, filetype) or nil
      state.popup:pane('doc', doc or {})
      state.doc_src, state.has_doc = src, doc ~= nil
      M.stats.panes = M.stats.panes + 1
    end
    local ms = (vim.uv.hrtime() - t0) / 1e6
    M.stats.ms, M.stats.max_ms = M.stats.ms + ms, math.max(M.stats.max_ms, ms)
    return
  end
  local last = math.min(#items, top + rows - 1)
  local ctxs, draw = blink.contexts(context, vim.list_slice(items, top, last))
  local cols = tree.columns(draw, context)
  if cmdline then
    -- The person's cmdline columns, with the kind's badge in front as in
    -- insert mode; the kind what the command line completes.
    cols.badge = true
    local compltype = vim.fn.getcmdcompltype()
    local icons = config.appearance and config.appearance.kind_icons or {}
    for i, ctx in ipairs(ctxs) do
      ctxs[i] = tree.cmdline_kind(ctx, compltype, icons)
    end
  end
  local ui = require('devhub').gui.ui
  local doc = src and doc_nodes(items, top, rows, context, src, filetype, ctxs) or nil
  local node, rel = tree.build(ui, {
    ctxs = ctxs, draw = draw, cols = cols, top = top, count = #items, selected = selected,
    doc = doc, doc_max_height = M.config.doc_max_height, on_click = M._click,
  })
  if state.popup then
    state.popup:update(node)
  else
    local w = width(config)
    -- (on the command line: above its box, as Neovim's wildmenu)
    state.popup = require('devhub').gui.popup {
      anchor = anchor, placement = not cmdline and 'below' or nil, component = node, close_on = {},
      min_width = w, max_width = w,
    }
    state.anchor = key
    if not state.popup then
      error 'gui.popup answered nothing'
    end
  end
  state.items, state.top, state.count, state.rel = items, top, #items, rel
  state.doc_src, state.has_doc = src, doc ~= nil
  local ms = (vim.uv.hrtime() - t0) / 1e6
  M.stats.trees, M.stats.ms, M.stats.max_ms = M.stats.trees + 1, M.stats.ms + ms, math.max(M.stats.max_ms, ms)
end

--- A row clicked (`index` in all items): a click selects it, as the keys
--- do; a double click accepts it. Both through blink's own API, so the
--- keys and everything built on blink's selection are as they were.
function M._click(index, clicks)
  local cmp = blink.cmp()
  if not cmp or not cmp.is_menu_visible() then
    return
  end
  if (clicks or 1) >= 2 then
    blink.accept(index)
  elseif cmp.get_selected_item_idx() ~= index then
    blink.select(index)
  end
end

--- Draw at the end of this tick (blink's events of one key come together).
function M.schedule()
  if state.pending then
    return
  end
  state.pending = true
  vim.schedule(function()
    local ok, err = pcall(render)
    if not ok then
      fall_back(err)
    end
  end)
end

local routed = false
local function route()
  if routed then
    return
  end
  routed = blink.route_doc_scroll(function(amount)
    if M.active() and state.popup and state.popup:is_open() and state.has_doc then
      state.popup:scroll(amount, 'doc')
      return true
    end
    return false
  end)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  broken = false
  local group = vim.api.nvim_create_augroup('blink_ui_devhub', { clear = true })
  -- blink's windows, hidden as they open: never drawn, still real. (In
  -- WinNew a window still shows the buffer it was split from; by
  -- BufWinEnter it shows blink's.)
  vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter' }, {
    group = group,
    callback = function()
      if package.loaded['blink.cmp.completion.windows.menu'] and M.active() and menu_mode() then
        if blink.ok() then
          blink.hide(true)
        else
          fall_back 'its internals moved'
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'BlinkCmpMenuOpen', 'BlinkCmpShow', 'BlinkCmpListSelect' },
    callback = function()
      if M.active() and menu_mode() then
        route()
        M.schedule()
      end
    end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'BlinkCmpMenuClose', 'BlinkCmpHide' },
    callback = function()
      reset()
    end,
  })
  -- A new mode, a new menu (DevHub closes a command line's popup itself).
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'CmdlineEnter', 'CmdlineLeave' }, {
    group = group,
    callback = function()
      reset()
    end,
  })
end

return M
