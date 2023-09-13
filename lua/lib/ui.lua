--- UI widgets module
-- widgets for paging, tabs, lists, dials, sliders, etc.
--
-- @module lib.UI

-- written as norns' ui.lua
-- @release v1.0.3
-- @author Mark Eats
-- norns ui.lua first committed by @tehn November 28, 2018
-- adapted for seamstress by @ryleelyman

local UI = {}
UI.__index = UI

-------- Pages --------

--- Pages
-- @section Pages

UI.Pages = {}
UI.Pages.__index = UI.Pages
setmetatable(UI.Pages, { __index = UI })

--- Create a new Pages object
-- @tparam number index Selected page, defaults to 1.
-- @tparam number num_pages Total number of pages, defaults to 3.
-- @param active_color `{r, g, b}`, defaults to `{100, 100, 100}`.
-- @param inactive_color `{r, g, b}`, defaults to `{20, 20, 20}`.
-- @tparam integer window 1 for main window, 2 for params, defaults to 1.
-- @treturn Pages Instance of Pages.
function UI.Pages.new(index, num_pages, active_color, inactive_color, window)
  local pages = {
    index = index or 1,
    num_pages = num_pages or 3,
    window = window or 1,
    active_color = active_color or { 100, 100, 100 },
    inactive_color = inactive_color or { 20, 20, 20 },
  }
  setmetatable(pages, UI.Pages)
  return pages
end

--- Set selected page.
-- @tparam number index Page number.
function UI.Pages:set_index(index)
  self.index = util.clamp(index, 1, self.num_pages)
end

--- Set selected page using delta.
-- @tparam number delta Number to move from selected page.
-- @tparam boolean wrap Boolean, true to wrap pages.
function UI.Pages:set_index_delta(delta, wrap)
  local index = self.index + delta
  if wrap then
    while index > self.num_pages do
      index = index - self.num_pages
    end
    while index < 1 do
      index = index + self.num_pages
    end
  end
  self:set_index(index)
end

--- Redraw Pages.
-- Call when changed.
function UI.Pages:redraw()
  local dot_height = util.clamp(util.round(64 / self.num_pages - 2), 1, 4)
  local dot_gap = util.round(util.linlin(1, 4, 1, 2, dot_height))
  local dots_y = util.round((64 - self.num_pages * dot_height - (self.num_pages - 1) * dot_gap) * 0.5)
  for i = 1, self.num_pages do
    if i == self.index then
      screen.color(table.unpack(self.active_color))
    else
      screen.color(table.unpack(self.inactive_color))
    end
    screen.move(self.window == 1 and screen.width - 1 or screen.params_width - 1, dots_y)
    screen.rect(1, dot_height)
    dots_y = dots_y + dot_height + dot_gap
  end
end

-------- Tabs --------

--- Tabs
-- @section Tabs

UI.Tabs = {}
UI.Tabs.__index = UI.Tabs

--- Create a new Tabs object.
-- @tparam number index Selected tab, defaults to 1.
-- @tparam {string,...} titles Table of strings for tab titles.
-- @param active_color {r, g, b}, defaults to {255, 255, 255}.
-- @param inactive_color {r, g, b}, defaults to {80, 80, 80}.
-- @tparam integer window 1 for main window, 2 for params, defaults to 1.
-- @treturn Tabs Instance of Tabs.
function UI.Tabs.new(index, titles, active_color, inactive_color, window)
  local tabs = {
    index = index or 1,
    titles = titles or {},
    window = window or 1,
    active_color = active_color or { 255, 255, 255 },
    inactive_color = inactive_color or { 80, 80, 80 },
  }
  setmetatable(UI.Tabs, { __index = UI })
  setmetatable(tabs, UI.Tabs)
  return tabs
end

--- Set selected tab.
-- @tparam number index Tab number.
function UI.Tabs:set_index(index)
  self.index = util.clamp(index, 1, #self.titles)
end

--- Set selected tab using delta.
-- @tparam number delta Number to move from selected tab.
-- @tparam boolean wrap Boolean, true to wrap tabs.
function UI.Tabs:set_index_delta(delta, wrap)
  local index = self.index + delta
  local count = #self.titles
  if wrap then
    while index > count do
      index = index - count
    end
    while index < 1 do
      index = index + count
    end
  end
  self:set_index(index)
end

--- Redraw Tabs.
-- Call when changed.
function UI.Tabs:redraw()
  local MARGIN = 8
  local GUTTER = 14
  local WIDTH = self.window == 1 and screen.width or screen.params_width
  local col_width = (WIDTH - (MARGIN * 2) - GUTTER * (#self.titles - 1)) / #self.titles
  for i = 1, #self.titles do
    if i == self.index then
      screen.color(table.unpack(self.active_color))
    else
      screen.color(table.unpack(self.inactive_color))
    end
    screen.move(MARGIN + col_width * 0.5 + ((col_width + GUTTER) * (i - 1)), 6)
    local str = util.trim_string_to_width(self.titles[i], col_width)
    screen.text_center(str)
  end
end

--- Use to process tabs clicks; responds on mouse release
-- @param x x-coordinate
-- @param y y-coordinate
-- @param state 1 for a press, 0 for a release
-- @param button bitmask for which button was pressed
function UI.Tabs:click(x, y, state, button)
  if button ~= 1 or state ~= 0 then
    return
  end
  local MARGIN = 8
  local WIDTH = self.window == 1 and screen.width or screen.params_width
  if y > 14 then
    return
  end
  if x < MARGIN or x > WIDTH - MARGIN then
    return
  end
  local idx = util.linlin(MARGIN, WIDTH - MARGIN, 1, #self.titles, x)
  self:set_index(math.floor(idx))
end

-------- List --------

--- List
-- @section List
UI.List = {}
UI.List.__index = UI.List

--- Create a new List object.
-- @tparam number x X position, defaults to 0.
-- @tparam number y Y position, defaults to 0.
-- @tparam number index Selected entry, defaults to 1.
-- @tparam {string,...} entries Table of strings for list entries.
-- @param active_color {r, g, b}, defaults to {255, 255, 255}
-- @param inactive_color {r, g, b}, defaults to {80, 80, 80}
-- @tparam integer window 1 for main window, 2 for params, defaults to 1.
-- @treturn List Instance of List.
function UI.List.new(x, y, index, entries, active_color, inactive_color, window)
  local list = {
    x = x or 0,
    y = y or 0,
    index = index or 1,
    entries = entries or {},
    text_align = "left",
    active = true,
    window = window or 1,
    active_color = { 255, 255, 255 },
    inactive_color = { 80, 80, 80 },
  }
  setmetatable(UI.List, { __index = UI })
  setmetatable(list, UI.List)
  return list
end

--- Set selected entry.
-- @tparam number index Entry number.
function UI.List:set_index(index)
  self.index = util.clamp(index, 1, #self.entries)
end

--- Set selected list using delta.
-- @tparam number delta Number to move from selected entry.
-- @tparam boolean wrap Boolean, true to wrap list.
function UI.List:set_index_delta(delta, wrap)
  local index = self.index + delta
  local count = #self.entries
  if wrap then
    while index > count do
      index = index - count
    end
    while index < 1 do
      index = index + count
    end
  end
  self:set_index(index)
end

--- Set selected list's active state.
-- @tparam boolean state Boolean, true for active.
function UI.List:set_active(state)
  self.active = state
end

--- Redraw List.
-- Call when changed.
function UI.List:redraw()
  for i = 1, #self.entries do
    if self.active and i == self.index then
      screen.color(table.unpack(self.active_color))
    else
      screen.color(table.unpack(self.inactive_color))
    end
    screen.move(self.x, self.y + 5 + (i - 1) * 11)
    local entry = self.entries[i] or ""
    if self.text_align == "center" then
      screen.text_center(entry)
    elseif self.text_align == "right" then
      screen.text_right(entry)
    else
      screen.text(entry)
    end
  end
end

-------- ScrollingList --------

--- ScrollingList
-- @section Scrollinglist
UI.ScrollingList = {}
UI.ScrollingList.__index = UI.ScrollingList

--- Create a new ScrollingList object.
-- @tparam number x X position, defaults to 0.
-- @tparam number y Y position, defaults to 0.
-- @tparam number index Selected entry, defaults to 1.
-- @tparam {string,...} entries Table of strings for list entries.
-- @param active_color {r, g, b}, defaults to {255, 255, 255}.
-- @param inactive_color {r, g, b}, defaults to {80, 80, 80}.
-- @tparam integer window 1 for main window, 2 for params, defaults to 1.
-- @treturn ScrollingList Instance of ScrollingList.
function UI.ScrollingList.new(x, y, index, entries, active_color, inactive_color, window)
  local list = {
    x = x or 0,
    y = y or 0,
    index = index or 1,
    entries = entries or {},
    num_visible = 5,
    num_above_selected = 1,
    text_align = "left",
    active = true,
    window = window or 1,
    active_color = active_color or { 255, 255, 255 },
    inactive_color = inactive_color or { 80, 80, 80 },
  }
  setmetatable(UI.ScrollingList, { __index = UI })
  setmetatable(list, UI.ScrollingList)
  return list
end

--- Set selected entry.
-- @tparam number index Entry number.
function UI.ScrollingList:set_index(index)
  self.index = util.clamp(index, 1, #self.entries)
end

--- Set selected scrolling list using delta.
-- @tparam number delta Number to move from selected entry.
-- @tparam boolean wrap Boolean, true to wrap list.
function UI.ScrollingList:set_index_delta(delta, wrap)
  local index = self.index + delta
  local count = #self.entries
  if wrap then
    while index > count do
      index = index - count
    end
    while index < 1 do
      index = index + count
    end
  end
  self:set_index(index)
end

--- Set selected scrolling list's active state.
-- @tparam boolean state Boolean, true for active.
function UI.ScrollingList:set_active(state)
  self.active = state
end

--- Redraw ScrollingList.
-- Call when changed.
function UI.ScrollingList:redraw()
  local num_entries = #self.entries
  local scroll_offset = self.index - 1 - math.max(self.index - (num_entries - 2), 0)
  scroll_offset = scroll_offset
    - util.linlin(num_entries - self.num_above_selected, num_entries, self.num_above_selected, 0, self.index - 1) -- For end of list
  for i = 1, self.num_visible do
    if self.active and self.index == i + scroll_offset then
      screen.color(table.unpack(self.active_color))
    else
      screen.color(table.unpack(self.inactive_color))
    end
    screen.move(self.x, self.y + 5 + (i - 1) * 11)
    local entry = self.entries[i + scroll_offset] or ""
    if self.text_align == "center" then
      screen.text_center(entry)
    elseif self.text_align == "right" then
      screen.text_right(entry)
    else
      screen.text(entry)
    end
  end
end

-------- Message --------

--- Message
-- @section Message
UI.Message = {}
UI.Message.__index = UI.Message

--- Create a new Message object.
-- @tparam [string,...] text_array Array of lines of text.
-- @param active_color {r, g, b}, defaults to {255, 255, 255}.
-- @param inactive_color {r, g, b}, defaults to {80, 80, 80}.
-- @tparam integer window 1 for the main window, 2 for the params window.
-- @treturn Message Instance of Message.
function UI.Message.new(text_array, active_color, inactive_color, window)
  local message = {
    text = text_array or {},
    active = true,
    active_color = active_color or { 255, 255, 255 },
    inactive_color = inactive_color or { 80, 80, 80 },
    window = window or 1,
  }
  setmetatable(UI.Message, { __index = UI })
  setmetatable(message, UI.Message)
  return message
end

--- Set message's active state.
-- @tparam boolean state Boolean, true for active.
function UI.Message:set_active(state)
  self.active = state
end

--- Redraw Message.
-- Call when changed.
function UI.Message:redraw()
  local LINE_HEIGHT = 11
  local y = util.round(34 - LINE_HEIGHT * (#self.text - 1) * 0.5)
  for i = 1, #self.text do
    if self.active then
      screen.color(table.unpack(self.active_color))
    else
      screen.color(table.unpack(self.inactive_color))
    end
    screen.move(self.window == 1 and screen.width / 2 or screen.params_width / 2, y)
    screen.text_center(self.text[i])
    y = y + 11
  end
end

-------- Slider --------

--- Slider
-- @section Slider
UI.Slider = {}
UI.Slider.__index = UI.Slider

--- Create a new Slider object.
-- @tparam number x X position, defaults to 0.
-- @tparam number y Y position, defaults to 0.
-- @tparam number width Width of slider, defaults to 3.
-- @tparam number height Height of slider, defaults to 36.
-- @tparam number value Current value, defaults to 0.
-- @tparam number min_value Minimum value, defaults to 0.
-- @tparam number max_value Maximum value, defaults to 1.
-- @tparam table markers Array of marker positions.
-- @tparam string direction the direction of the slider "up" (defult), down, left, right
-- @param colors table of background_color, inactive_color and active_color, all {r, g, b}
-- @tparam integer window 1 for the main window, 2 for the params window.
-- @treturn Slider Instance of Slider.
function UI.Slider.new(x, y, width, height, value, min_value, max_value, markers, direction, colors, window)
  local slider = {
    x = x or 0,
    y = y or 0,
    width = width or 3,
    height = height or 36,
    value = value or 0,
    min_value = min_value or 0,
    max_value = max_value or 1,
    markers = markers or {},
    active = true,
    direction = direction or "up",
    background_color = colors.background_color or { 50, 50, 50 },
    inactive_color = colors.inactive_color or { 80, 80, 80 },
    active_color = colors.active_color or { 255, 255, 255 },
    window = window or 1,
  }
  local acceptableDirections = { "up", "down", "left", "right" }

  if acceptableDirections[direction] == nil then
    direction = acceptableDirections[1]
  end
  setmetatable(UI.Slider, { __index = UI })
  setmetatable(slider, UI.Slider)
  return slider
end

--- Set value.
-- @tparam number number Value number.
function UI.Slider:set_value(number)
  self.value = util.clamp(number, self.min_value, self.max_value)
end

--- Set value using delta.
-- @tparam number delta Number.
function UI.Slider:set_value_delta(delta)
  self:set_value(self.value + delta)
end

--- Set marker position.
-- @tparam number id Marker number.
-- @tparam number position Marker position number.
function UI.Slider:set_marker_position(id, position)
  self.markers[id] = util.clamp(position, self.min_value, self.max_value)
end

--- Set slider's active state.
-- @tparam boolean state Boolean, true for active.
function UI.Slider:set_active(state)
  self.active = state
end

--- Redraw Slider.
-- Call when changed.
function UI.Slider:redraw()
  screen.move(self.x + 0.5, self.y + 0.5)
  screen.color(table.unpack(self.background_color))

  --draws the perimeter
  if self.direction == "up" or self.direction == "down" then
    screen.rect(self.width - 1, self.height - 1)
  elseif self.direction == "left" or self.direction == "right" then
    screen.rect(self.width - 1, self.height - 1)
  end

  --draws the markers
  for _, v in pairs(self.markers) do
    if self.direction == "up" then
      screen.move(self.x - 2, util.round(self.y + util.linlin(self.min_value, self.max_value, self.height - 1, 0, v)))
      screen.rect(self.width + 4, 1) --original
    elseif self.direction == "down" then
      screen.move(self.x - 2, util.round(self.y + util.linlin(self.min_value, self.max_value, 0, self.height - 1, v)))
      screen.rect(self.width + 4, 1)
    elseif self.direction == "left" then
      screen.move(util.round(self.x + util.linlin(self.min_value, self.max_value, self.width - 1, 0, v)), self.y - 2)
      screen.rect(1, self.height + 4)
    elseif self.direction == "right" then
      screen.move(util.round(self.x + util.linlin(self.min_value, self.max_value, 0, self.width - 1, v)), self.y - 2)
      screen.rect(1, self.height + 4)
    end
  end

  local filled_amount
  if self.active then
    screen.color(table.unpack(self.active_color))
  else
    screen.color(table.unpack(self.inactive_color))
  end
  if self.direction == "up" then
    filled_amount = util.round(util.linlin(self.min_value, self.max_value, 0, self.height, self.value))
    screen.move(self.x, self.y + self.height - filled_amount)
    screen.rect(self.width, filled_amount)
  elseif self.direction == "down" then
    filled_amount = util.round(util.linlin(self.min_value, self.max_value, 0, self.height, self.value)) --same as up
    screen.move(self.x, self.y)
    screen.rect(self.width, filled_amount)
  elseif self.direction == "left" then
    filled_amount = util.round(util.linlin(self.min_value, self.max_value, 0, self.width, self.value))
    screen.move(self.x + self.width - filled_amount, self.y)
    screen.rect(filled_amount, self.height)
  elseif self.direction == "right" then
    filled_amount = util.round(util.linlin(self.min_value, self.max_value, 0, self.width, self.value))
    screen.move(self.x, self.y)
    screen.rect(filled_amount, self.height)
  end

end

-------- Dial --------

--- Dial
-- @section Dial
UI.Dial = {}
UI.Dial.__index = UI.Dial

--- Create a new Dial object.
-- @tparam number x X position, defaults to 0.
-- @tparam number y Y position, defaults to 0.
-- @tparam number size Diameter of dial, defaults to 22.
-- @tparam number value Current value, defaults to 0.
-- @tparam number min_value Minimum value, defaults to 0.
-- @tparam number max_value Maximum value, defaults to 1.
-- @tparam number rounding Sets precision to round value to, defaults to 0.01.
-- @tparam number start_value Sets where fill line is drawn from, defaults to 0.
-- @tparam table markers Array of marker positions.
-- @tparam string units String to display after value text.
-- @tparam string title String to be displayed instead of value text.
-- @param colors table of background_color, inactive_color, and active_color, all {r, g, b}
-- @tparam integer window 1 for main window, 2 for params, defaults to 1.
-- @treturn Dial Instance of Dial.
function UI.Dial.new(
  x,
  y,
  size,
  value,
  min_value,
  max_value,
  rounding,
  start_value,
  markers,
  units,
  title,
  colors,
  window
)
  local markers_table = markers or {}
  min_value = min_value or 0
  local dial = {
    x = x or 0,
    y = y or 0,
    size = size or 22,
    value = value or 0,
    min_value = min_value,
    max_value = max_value or 1,
    rounding = rounding or 0.01,
    start_value = start_value or min_value,
    units = units,
    title = title or nil,
    active = true,
    background_color = colors.background_color or { 50, 50, 50 },
    inactive_color = colors.inactive_color or { 80, 80, 80 },
    active_color = colors.active_color or { 255, 255, 255 },
    window = window or 1,
    _start_angle = math.pi * 0.7,
    _end_angle = math.pi * 2.3,
    _markers = {},
    _marker_points = {},
  }
  setmetatable(UI.Dial, { __index = UI })
  setmetatable(dial, UI.Dial)
  for k, v in pairs(markers_table) do
    dial:set_marker_position(k, v)
  end
  return dial
end

--- Set value.
-- @tparam number number Value number.
function UI.Dial:set_value(number)
  self.value = util.clamp(number, self.min_value, self.max_value)
end

--- Set value using delta.
-- @tparam number delta Number.
function UI.Dial:set_value_delta(delta)
  self:set_value(self.value + delta)
end

--- Set marker position.
-- @tparam number id Marker number.
-- @tparam number position Marker position number.
function UI.Dial:set_marker_position(id, position)
  self._markers[id] = util.clamp(position, self.min_value, self.max_value)

  local radius = self.size * 0.5
  local marker_length = 3

  local marker_in = radius - marker_length
  local marker_out = radius + marker_length
  local marker_angle =
    util.linlin(self.min_value, self.max_value, self._start_angle, self._end_angle, self._markers[id])
  local x_center = self.x + self.size / 2
  local y_center = self.y + self.size / 2
  self._marker_points[id] = {}
  self._marker_points[id].x1 = x_center + math.cos(marker_angle) * marker_in
  self._marker_points[id].y1 = y_center + math.sin(marker_angle) * marker_in
  self._marker_points[id].x2 = x_center + math.cos(marker_angle) * marker_out
  self._marker_points[id].y2 = y_center + math.sin(marker_angle) * marker_out
end

--- Set dial's active state.
-- @tparam boolean state Boolean, true for active.
function UI.Dial:set_active(state)
  self.active = state
end

--- Redraw Dial.
-- Call when changed.
function UI.Dial:redraw()
  local radius = self.size * 0.5

  local fill_start_angle =
    util.linlin(self.min_value, self.max_value, self._start_angle, self._end_angle, self.start_value)
  local fill_end_angle = util.linlin(self.min_value, self.max_value, self._start_angle, self._end_angle, self.value)

  if fill_end_angle < fill_start_angle then
    local temp_angle = fill_start_angle
    fill_start_angle = fill_end_angle
    fill_end_angle = temp_angle
  end

  screen.color(table.unpack(self.background_color))
  screen.move(self.x + radius, self.y + radius)
  screen.arc(radius - 0.5, self._start_angle, self._end_angle)

  for _, v in pairs(self._marker_points) do
    screen.move(v.x1, v.y1)
    screen.line(v.x2, v.y2)
    screen.stroke()
  end

  if self.active then
    screen.color(table.unpack(self.active_color))
  else
    screen.color(table.unpack(self.inactive_color))
  end
  screen.move(self.x + radius, self.y + radius)
  screen.arc(radius - 0.5, fill_start_angle, fill_end_angle)
  screen.arc(radius + 0.5, fill_start_angle, fill_end_angle)
  screen.line_width(1)

  local title
  if self.title then
    title = self.title
  else
    title = util.round(self.value, self.rounding)
    if self.units then
      title = title .. " " .. self.units
    end
  end
  screen.move(self.x + radius, self.y + self.size + 6)
  screen.text_center(title)
  screen.reset()
end

-------- PlaybackIcon --------

--- PlaybackIcon
-- @section PlaybackIcon
UI.PlaybackIcon = {}
UI.PlaybackIcon.__index = UI.PlaybackIcon

--- Create a new PlaybackIcon object.
-- @tparam number x X position, defaults to 0.
-- @tparam number y Y position, defaults to 0.
-- @tparam number size Icon size, defaults to 6.
-- @tparam number status Status number. 1 = Play, 2 = Reverse Play, 3 = Pause, 4 = Stop. Defaults to 1.
-- @param active_color {r, g, b}, defaults to {255, 255, 255},
-- @param inactive_color {r, g, b}, defaults to {80, 80, 80},
-- @tparam integer window 1 for the main window, 2 for the params window
-- @treturn PlaybackIcon Instance of PlaybackIcon.
function UI.PlaybackIcon.new(x, y, size, status, active_color, inactive_color, window)
  local playback_icon = {
    x = x or 0,
    y = y or 0,
    size = size or 6,
    status = status or 1,
    active = true,
    active_color = active_color or { 255, 255, 255 },
    inactive_color = inactive_color or { 80, 80, 80 },
    window = window or 1,
  }
  setmetatable(UI.PlaybackIcon, { __index = UI })
  setmetatable(playback_icon, UI.PlaybackIcon)
  return playback_icon
end

--- Set PlaybackIcon's status.
-- @tparam number status Status number. 1 = Play, 2 = Reverse Play, 3 = Pause, 4 = Stop.
function UI.PlaybackIcon:set_status(status)
  self.status = status
end

--- Set PlaybackIcon's active state.
-- @tparam boolean state Boolean, true for active.
function UI.PlaybackIcon:set_active(state)
  self.active = state
end

--- Redraw PlaybackIcon.
-- Call when changed.
function UI.PlaybackIcon:redraw()
  if self.active then
    screen.color(table.unpack(self.active_color))
  else
    screen.color(table.unpack(self.inactive_color))
  end
  -- Play
  if self.status == 1 then
    screen.triangle(self.x, self.y, self.x + self.size, self.y + self.size * 0.5, self.x, self.y + self.size)
  -- Reverse Play
  elseif self.status == 2 then
    screen.triangle(
      self.x + self.size,
      self.y,
      self.x,
      self.y + self.size * 0.5,
      self.x + self.size,
      self.y + self.size
    )
  -- Pause
  elseif self.status == 3 then
    screen.move(self.x, self.y)
    screen.rect_fill(util.round(self.size * 0.4), self.size)
    screen.move_rel(util.round(self.size * 0.6), 0)
    screen.rect_fill(util.round(self.size * 0.4), self.size)
  -- Stop
  else
    screen.move(self.x, self.y)
    screen.rect(self.size, self.size)
  end
  screen.reset()
end

return UI
