-- The menu as a devhub.nvim component tree, pure: given blink's draw
-- contexts for the rows in sight, the person's draw config and the selected
-- item's documentation, the tree. No blink and no DevHub here (tests/spec.lua).

local M = {}

--- The first row in sight, so that the selection stays `so` rows from either
--- edge as blink's own window keeps it: moved as little as it can be.
function M.window(top, selected, count, rows, so)
  so = math.min(so or 2, math.floor((rows - 1) / 2))
  top = top or 1
  if selected then
    if selected < top + so then
      top = selected - so
    elseif selected > top + rows - 1 - so then
      top = selected - rows + 1 + so
    end
  end
  return math.max(1, math.min(top, count - rows + 1))
end

--- Which component draws what, from the person's draw.columns: the kind's
--- badge (kind_icon), the label (label, with its detail), and every other
--- component (kind, label_description, source_name, …) in the column at the
--- right, in their order.
--- (columns may be a function of blink's context, as blink allows.)
function M.columns(draw, context)
  local cols = { badge = false, label = false, right = {} }
  local columns = draw and draw.columns
  if type(columns) == 'function' then
    columns = columns(context)
  end
  if type(columns) ~= 'table' then
    columns = { { 'kind_icon' }, { 'label', 'label_description', gap = 1 } }
  end
  for _, column in ipairs(columns) do
    for _, name in ipairs(column) do
      if name == 'kind_icon' then
        cols.badge = true
      elseif name == 'label' then
        cols.label = true
      else
        table.insert(cols.right, name)
      end
    end
  end
  return cols
end

-- A component's text and group for this row, as the person's config makes
-- them (its own `text`/`highlight` functions on blink's context).
local function component(draw, name, ctx)
  local c = draw and draw.components and draw.components[name]
  local text, hl
  if c and type(c.text) == 'function' then
    local ok, t = pcall(c.text, ctx)
    text = ok and type(t) == 'string' and t or nil
  end
  if c and type(c.highlight) == 'string' then
    hl = c.highlight
  elseif c and type(c.highlight) == 'function' then
    local ok, h = pcall(c.highlight, ctx)
    hl = ok and type(h) == 'string' and h or nil
  end
  return text, hl
end
M.component = component

--- A label as runs: its matched characters (blink's byte offsets) in
--- BlinkCmpLabelMatch, the rest in BlinkCmpLabel (or Deprecated).
function M.label_runs(label, matched, deprecated)
  local is = {}
  for _, i in ipairs(matched or {}) do
    is[i] = true
  end
  local base = deprecated and 'BlinkCmpLabelDeprecated' or 'BlinkCmpLabel'
  local runs, cur, cur_m = {}, {}, nil
  local i = 0
  while i < #label do
    local len = vim.str_utf_end(label, i + 1) + 1
    local m = is[i] == true
    if cur_m ~= nil and m ~= cur_m then
      table.insert(runs, { text = table.concat(cur), hl = cur_m and 'BlinkCmpLabelMatch' or base })
      cur = {}
    end
    table.insert(cur, label:sub(i + 1, i + len))
    cur_m = m
    i = i + len
  end
  if #cur > 0 then
    table.insert(runs, { text = table.concat(cur), hl = cur_m and 'BlinkCmpLabelMatch' or base })
  end
  for _, r in ipairs(runs) do
    r.mono = true
    r.strike = deprecated or nil
  end
  return runs
end

-- How far the menu's content is in from its band, across as down: DevHub
-- insets the band from the popup's line on all four sides alike, so the text
-- is as far from the line on every side (a row's own height adds about a
-- pixel down: the label's line is a little taller than the badge).
M.INSET = 2

--- One row: the kind's badge, the label (lined up with the word typed when
--- `anchor`), and the right column, truly at the right.
function M.row(ui, ctx, draw, cols, anchor)
  local children = {}
  if cols.badge then
    local icon = component(draw, 'kind_icon', ctx) or ctx.kind_icon or ''
    icon = vim.trim(icon)
    if icon == '' then
      icon = ' '
    end
    table.insert(children, ui.badge(icon, { size = 'sm', mono = true, hl = ctx.kind_hl }))
  end
  local runs = M.label_runs(ctx.label or '', ctx.label_matched_indices, ctx.deprecated)
  if ctx.label_detail and ctx.label_detail ~= '' then
    table.insert(runs, { text = ctx.label_detail, hl = 'BlinkCmpLabelDetail', mono = true })
  end
  table.insert(children, ui.text(runs, { grow = true, anchor = anchor or nil }))
  local right = {}
  for _, name in ipairs(cols.right) do
    local text, hl = component(draw, name, ctx)
    if text == nil then
      text = name == 'kind' and ctx.kind or name == 'label_description' and ctx.label_description
        or name == 'source_name' and ctx.source_name or nil
    end
    if type(text) == 'string' and vim.trim(text) ~= '' then
      table.insert(right, { text = vim.trim(text), hl = hl or 'BlinkCmpLabelDescription' })
      table.insert(right, '  ')
    end
  end
  table.remove(right)
  if #right > 0 then
    table.insert(children, ui.text(right, { size = 'sm' }))
  end
  return ui.hstack(vim.tbl_extend('force', { gap = 6, align = 'center', pad = { 1, M.INSET } }, children))
end

--- The selected item's documentation as a node, or nil: its documentation
--- (markdown as markdown, plain text as text) and, when the right column did
--- not show it, its detail as code in the buffer's language.
function M.doc(ui, item, shown, filetype)
  if type(item) ~= 'table' then
    return nil
  end
  local parts = {}
  local detail = type(item.detail) == 'string' and vim.trim(item.detail) or ''
  if detail ~= '' and detail ~= shown then
    table.insert(parts, ui.md(string.format('```%s\n%s\n```', filetype or '', detail), { size = 'sm' }))
  end
  local d = item.documentation
  local kind = 'markdown'
  if type(d) == 'table' then
    kind = d.kind or 'markdown'
    d = d.value
  end
  if type(d) == 'string' and vim.trim(d) ~= '' then
    if kind == 'plaintext' then
      table.insert(parts, ui.text(vim.trim(d), { wrap = true, size = 'sm' }))
    else
      table.insert(parts, ui.md(vim.trim(d), { size = 'sm' }))
    end
  end
  if #parts == 0 then
    return nil
  end
  return parts
end

--- The documentation's pane: its text as far in from the hairline above it
--- and from the line at the sides and below as the rows' is.
function M.pane(ui, doc, max_height)
  return ui.stack(vim.tbl_extend('force', { pane = 'doc', max_height = max_height or 240, gap = 6, pad = { M.INSET, M.INSET } }, doc or {}))
end

--- The whole popup: the list (the rows in sight, the selected one banded),
--- where it is in a longer list, and the documentation in a pane under it.
---   o = { ctxs, draw, cols, top, count, selected (in all), doc (nodes),
---         doc_max_height (px) }
function M.build(ui, o)
  local rows = {}
  for i, ctx in ipairs(o.ctxs) do
    table.insert(rows, M.row(ui, ctx, o.draw, o.cols, i == 1))
  end
  local rel = o.selected and o.selected - o.top + 1 or 0
  if rel < 1 or rel > #rows then
    rel = 0
  end
  local list = ui.stack(vim.tbl_extend('force', { band = 'BlinkCmpMenuSelection' }, rows))
  list.selected = rel > 0 and rel or nil
  local children = { list }
  if o.count > #rows then
    local last = o.top + #rows - 1
    -- in as far as the rows' content
    table.insert(
      children,
      ui.hstack {
        pad = { 0, M.INSET },
        ui.text(string.format('%d–%d / %d', o.top, last, o.count), { size = 'xs', hl = 'BlinkCmpLabelDescription' }),
      }
    )
  end
  -- always there (empty: not drawn), so a new item's documentation is the
  -- pane's content alone (popup:pane)
  table.insert(children, M.pane(ui, o.doc, o.doc_max_height))
  return ui.stack(vim.tbl_extend('force', { gap = 3 }, children)), rel
end

return M
