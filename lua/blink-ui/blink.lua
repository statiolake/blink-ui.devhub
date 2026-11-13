-- The seams into blink.cmp, each behind pcall. Public: `require('blink.cmp')`'s
-- get_items / get_selected_item_idx / get_context / is_menu_visible and its
-- User autocmds. Internal (a blink that moved them leaves its own float):
--   blink.cmp.completion.windows.menu / .documentation  their windows' buffers
--     (to hide the windows) and the documentation's scroll_up / scroll_down
--     (scroll_documentation_* keys scroll the popup's pane instead);
--   blink.cmp.completion.windows.render.context  get_from_items: the draw
--     context blink gives its own components (label, matched indices, kind,
--     kind_icon, kind_hl, …);
--   blink.cmp.sources.lib  resolve: the item with its documentation (cached
--     by blink, so the language server is not asked twice);
--   blink.cmp.completion.list  select: an item selected by its index, as
--     select_next/select_prev select (a row clicked).

local M = {}

local function mod(name)
  local ok, m = pcall(require, name)
  return ok and type(m) == 'table' and m or nil
end

--- Select the item at `index` (in all), as blink's select_next/prev would:
--- its own list.select, else counted moves from the selection there is.
function M.select(index)
  local list = mod 'blink.cmp.completion.list'
  if list and type(list.select) == 'function' then
    vim.schedule(function()
      list.select(index)
    end)
    return true
  end
  local cmp = M.cmp()
  if not cmp then
    return false
  end
  local cur = cmp.get_selected_item_idx() or 0
  if index > cur then
    return cmp.select_next { count = index - cur } == true
  elseif index < cur then
    return cmp.select_prev { count = cur - index } == true
  end
  return true
end

--- Accept the item at `index` (in all): blink's own accept.
function M.accept(index)
  local cmp = M.cmp()
  return cmp ~= nil and type(cmp.accept) == 'function' and cmp.accept { index = index } == true
end

function M.cmp()
  return mod 'blink.cmp'
end

function M.config()
  local c = mod 'blink.cmp.config'
  return c and c.completion and c or nil
end

--- Whether every seam is where this plugin expects it.
function M.ok()
  local cmp = M.cmp()
  local menu = mod 'blink.cmp.completion.windows.menu'
  local docs = mod 'blink.cmp.completion.windows.documentation'
  local ctx = mod 'blink.cmp.completion.windows.render.context'
  local sources = mod 'blink.cmp.sources.lib'
  return cmp ~= nil and M.config() ~= nil
    and type(cmp.get_items) == 'function' and type(cmp.get_context) == 'function'
    and type(cmp.get_selected_item_idx) == 'function' and type(cmp.is_menu_visible) == 'function'
    and menu ~= nil and type(menu.win) == 'table'
    and docs ~= nil and type(docs.win) == 'table' and type(docs.scroll_up) == 'function'
    and ctx ~= nil and type(ctx.get_from_items) == 'function'
    and sources ~= nil and type(sources.resolve) == 'function'
end

--- blink's menu and documentation windows (those showing their buffers):
--- inside DevHub the current window during WinNew is not the new one, so
--- they are found by buffer.
function M.windows()
  local bufs = {}
  for _, name in ipairs { 'blink.cmp.completion.windows.menu', 'blink.cmp.completion.windows.documentation' } do
    local m = mod(name)
    local buf = m and type(m.win) == 'table' and m.win.buf
    if type(buf) == 'number' then
      bufs[buf] = true
    end
  end
  local wins = {}
  if next(bufs) == nil then
    return wins
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
    if ok and bufs[buf] then
      table.insert(wins, win)
    end
  end
  return wins
end

--- Hide (or show again) blink's windows. Hidden they stay real: blink's
--- `is_menu_visible()`, its scrolling, preview and keys are untouched.
function M.hide(on)
  for _, win in ipairs(M.windows()) do
    local ok, config = pcall(vim.api.nvim_win_get_config, win)
    if ok and (config.hide == true) ~= on then
      pcall(vim.api.nvim_win_set_config, win, { hide = on })
    end
  end
end

--- blink's draw contexts for these items (errors are the caller's).
function M.contexts(context, items)
  local draw = M.config().completion.menu.draw
  return require('blink.cmp.completion.windows.render.context').get_from_items(context, draw, items), draw
end

--- fn(resolved item) once blink resolved it (at once when it is cached).
function M.resolve(context, item, fn)
  return pcall(function()
    require('blink.cmp.sources.lib').resolve(context, item):map(function(resolved)
      vim.schedule(function()
        fn(resolved or item)
      end)
    end)
  end)
end

local originals

--- Route blink's documentation scrolling (its scroll_documentation_* keys)
--- through scroll(amount) — negative is up — when it answers true; blink's
--- own otherwise. nil restores blink's.
function M.route_doc_scroll(scroll)
  local docs = mod 'blink.cmp.completion.windows.documentation'
  if not docs or type(docs.scroll_up) ~= 'function' then
    return false
  end
  if not originals then
    originals = { up = docs.scroll_up, down = docs.scroll_down }
  end
  if not scroll then
    docs.scroll_up, docs.scroll_down = originals.up, originals.down
    return true
  end
  docs.scroll_up = function(amount)
    if not scroll(-(amount or 4)) then
      return originals.up(amount)
    end
  end
  docs.scroll_down = function(amount)
    if not scroll(amount or 4) then
      return originals.down(amount)
    end
  end
  return true
end

return M
