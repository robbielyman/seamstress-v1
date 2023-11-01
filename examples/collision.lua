-- collision.
-- @eigen
--
-- inspired by the visualizations for the ATLAS experiments at CERN's LHC.

-- -------------------------------------------------------------------------
-- consts

FPS = 60

-- time in seconds between each collision
BANG_INTERVAL_S = 2

-- -------------------------------------------------------------------------
-- colors

COL_BG = { 0, 0, 0 }
COL_FLASH = { 250, 250, 250 }
COL_DETECTOR_BG = { 25, 21, 13 }
COL_PARTICLE = { 255, 165, 0 }
COL_BARS = { 253, 238, 0 }
COL_MUON = { 255, 0, 0 }
COL_BORDER = { 147, 112, 219 }
COL_RIPPLE = { 110, 105, 120 }

-- -------------------------------------------------------------------------
-- fading speed

-- how much time elements stay on screen between each bang
-- at 1, it will fade during the full duration between 2 collisions
-- at 1/2, it will stay for half this duration
-- at 2 it will only fade by half

FADE_T_INNER_RIPPLES = 1 / 1.5
FADE_T_RIPPLES = 1 / 1.5
FADE_T_PARTICLES = 1 / 4
FADE_T_HADRONS = 1 / 2
FADE_T_MUONS = 4

-- -------------------------------------------------------------------------
-- state

has_banged = false

frame_count = 1

muons = {}
particles = {}
hadrons = {}
ripples = {}

function pct_time_bang()
  local elapsed_s = frame_count * (1 / FPS)
  return (elapsed_s % BANG_INTERVAL_S) / BANG_INTERVAL_S
end

function bang()
  local nb_muons = math.random(1, 4)
  local nb_particles = math.random(10, 25)
  local nb_ripples = math.random(20, 40)

  hadrons = {}

  muons = {}
  for m = 1, nb_muons do
    local angle = math.random(100) / 100
    table.insert(muons, angle)

    table.insert(hadrons, { angle, math.random(100) / 100 })
  end

  particles = {}
  for m = 1, nb_particles do
    local angle = math.random(100) / 100
    local angle2 = math.random(10) / 100
    local dir = (math.random(2) - 1.5) * 2
    table.insert(particles, { angle, angle2, dir })

    table.insert(hadrons, { angle, math.random(100) / 100 })
  end

  ripples = {}
  for m = 1, nb_ripples do
    local angle = math.random(100) / 100
    local offset = math.random(100) / 100
    local radius = math.random(10, 100) / 100
    table.insert(ripples, { angle, offset, radius })
  end
end

-- -------------------------------------------------------------------------
-- core

function cos(x)
  return math.cos(math.rad(x * 360))
end

function sin(x)
  return -math.sin(math.rad(x * 360))
end

function points_dist(x1, y1, x2, y2)
  local dx = x1 - x2
  local dy = y1 - y2
  return math.sqrt(dx ^ 2 + dy ^ 2)
end

function point_in_circle(cx, cy, r, px, py)
  return (points_dist(cx, cy, px, py) <= r)
end

function color_scale(min_col, max_col, cursor)
  local r = min_col[1] + (max_col[1] - min_col[1]) * cursor
  local g = min_col[2] + (max_col[2] - min_col[2]) * cursor
  local b = min_col[3] + (max_col[3] - min_col[3]) * cursor
  return { r, g, b }
end

-- -------------------------------------------------------------------------
-- init

local clock_redraw
local clock_bang

function init()
  clock_redraw = clock.run(function()
    while true do
      clock.sleep(1 / FPS)
      redraw()
      frame_count = frame_count + 1
    end
  end)

  clock_bang = clock.run(function()
    while true do
      clock.sleep(BANG_INTERVAL_S)
      bang()
      frame_count = 1
      has_banged = true
    end
  end)
end

-- -------------------------------------------------------------------------
-- screen

function redraw()
  local screen_w, screen_h = screen.get_size()

  screen.clear()

  local center_x, center_y = screen_w / 2, screen_h / 2
  local outer_r = (screen_h / 2) * 3 / 4
  local inner_r = outer_r / 2
  local bar_max = (screen_h / 2) - outer_r

  local pct_bang = pct_time_bang()

  if has_banged and frame_count < 5 then
    -- flash
    screen.move(1, 1)
    screen.color(table.unpack(COL_FLASH))
    screen.rect_fill(screen_w, screen_h)
  else
    -- detector bg
    screen.move(center_x, center_y)
    screen.color(table.unpack(COL_DETECTOR_BG))
    screen.circle_fill(outer_r)
    screen.color(table.unpack(COL_BG))
    screen.circle_fill(inner_r)
  end

  -- inner (concentric) ripples
  if tab.count(muons) > 0 then
    local inner_ripples = { 1 / 9, 1 / 2, 1 / 2 + 1 / 8, 1 / 2 + 2 / 8, 1 / 2 + 3 / 8 }
    screen.color(table.unpack(color_scale(COL_BARS, COL_BG, pct_bang / FADE_T_INNER_RIPPLES)))
    for _, r_ratio in pairs(inner_ripples) do
      local r = inner_r * r_ratio
      for i = 1, 70 do
        if math.random(3) > 1 then
          local noize = (1 + math.random(10) / 100)
          local px = center_x + r * noize * cos(i / 70) * -1
          local py = center_y + r * noize * sin(i / 70)
          screen.pixel(px, py)
        end
      end
    end
  end

  -- ripples in detector
  screen.color(table.unpack(color_scale(COL_RIPPLE, COL_DETECTOR_BG, math.min(pct_bang / FADE_T_RIPPLES, 1))))
  for _, r in pairs(ripples) do
    local angle, offset, radius = table.unpack(r)
    local r = radius * outer_r * 3 / 4
    local ax = center_x + (offset * outer_r) * cos(angle) * -1
    local ay = center_y + (offset * outer_r) * sin(angle)

    -- if frame_count < 5 then
    --   screen.move(ax, ay)
    --   screen.circle(radius * outer_r * 3/4)
    -- end

    for i = 1, 100 do
      if math.random(3) > 1 then
        local px = ax + r * cos(i / 100) * -1
        local py = ay + r * sin(i / 100)
        if
          point_in_circle(center_x, center_y, outer_r, px, py)
          and not point_in_circle(center_x, center_y, inner_r, px, py)
        then
          screen.pixel(px, py)
        end
      end
    end
  end

  -- particles (orange curves)
  screen.color(table.unpack(color_scale(COL_FLASH, COL_PARTICLE, math.min(pct_bang / FADE_T_PARTICLES, 1))))
  for _, p in pairs(particles) do
    local angle, angle2, dir = table.unpack(p)
    local bx = center_x + outer_r * cos(angle) * -1
    local by = center_y + outer_r * sin(angle)

    local midx = center_x + outer_r / 2 * cos(angle + angle2 * dir) * -1
    local midy = center_y + outer_r / 2 * sin(angle + angle2 * dir)

    screen.curve(midx, midy, midx, midy, bx, by)
  end

  -- hadrons (outer bars)
  screen.color(table.unpack(color_scale(COL_BARS, COL_BG, pct_bang / FADE_T_HADRONS)))
  local offset = 0.01
  for _, h in pairs(hadrons) do
    local angle, amp = table.unpack(h)
    local ax = center_x + (outer_r + 3) * cos(angle - offset) * -1
    local ay = center_y + (outer_r + 3) * sin(angle - offset)

    local bx = center_x + (outer_r + 3) * cos(angle + offset) * -1
    local by = center_y + (outer_r + 3) * sin(angle + offset)

    local cx = center_x + (outer_r + amp * bar_max) * cos(angle - offset) * -1
    local cy = center_y + (outer_r + amp * bar_max) * sin(angle - offset)

    local dx = center_x + (outer_r + amp * bar_max) * cos(angle + offset) * -1
    local dy = center_y + (outer_r + amp * bar_max) * sin(angle + offset)

    -- screen.quad(bx, by, ax, ay, cx, cy, dx, dy)

    screen.move(bx, by)
    screen.line(ax, ay)
    screen.move(ax, ay)
    screen.line(cx, cy)
    screen.move(cx, cy)
    screen.line(dx, dy)
    screen.move(dx, dy)
    screen.line(bx, by)
  end

  -- muons (red lines)
  screen.move(center_x, center_y)
  screen.color(table.unpack(color_scale(COL_MUON, COL_BG, pct_bang / FADE_T_MUONS)))
  for _, angle in pairs(muons) do
    local bx = center_x + (screen_w / 2) * cos(angle) * -1
    local by = center_y + (screen_w / 2) * sin(angle)
    screen.line(bx, by)
  end

  -- detector boundaries
  screen.move(center_x, center_y)
  screen.color(table.unpack(COL_BORDER))
  screen.circle(outer_r)
  screen.circle(inner_r)

  screen.refresh()
end
