--- plasma!
-- written by @tehn for norns
-- adapted by @ryleelyman for seamstress
--
-- +/-                time
-- number keys        func
-- up/down            a
-- left/right         b
-- shift + up/down    c
-- shift + left/right d
--
-- submit new funcs!

abs = math.abs
floor = math.floor
sin = math.sin
cos = math.cos
sqrt = math.sqrt

func = {
	function(x, y)
		return abs(floor(16 * (sin(x / a + t * c) + cos(y / b + t * d)))) % 16
	end,
	function(x, y)
		return abs(floor(16 * (sin(x / y) * a + t * b))) % 16
	end,
	function(x, y)
		return abs(floor(16 * (sin(sin(t * a) * c + (t * b) + sqrt(y * y * (y * c) + x * (x / d)))))) % 16
	end,
}
f = 1
p = {}
t = 0
time = 0.02
a = 3.0
b = 5.0
c = 1.0
d = 1.1
alt = false

g = grid.connect()

function tick()
	while true do
		t = t + (time * 0.1)
		process()
		redraw()
		grid_redraw()
		clock.sleep(1 / 60)
	end
end

function init()
	print("hello")
	process()
	redraw()
	clock.run(tick)
end

function process()
	for x = 1, 16 do
		for y = 1, 16 do
			p[y * 16 + x] = func[f](x, y)
		end
	end
end

function grid_redraw()
	for y = 1, 16 do
		for x = 1, 16 do
			g:led(x, y, p[x + y * 16])
		end
	end
	g:refresh()
end

function screen.key(char, modifiers, _, state)
	if state == 1 then
		if char == "1" then
			f = 1
		elseif char == "2" then
			f = 2
		elseif char == "3" then
			f = 3
		elseif char == "-" then
			time = time - 0.001
		elseif char == "=" then
			time = time + 0.001
		elseif char.name == "up" then
			if tab.contains(modifiers, "shift") then
				c = c + 0.01
			else
				a = a + 0.01
			end
		elseif char.name == "down" then
			if tab.contains(modifiers, "shift") then
				c = c - 0.01
			else
				a = a - 0.01
			end
		elseif char.name == "left" then
			if tab.contains(modifiers, "shift") then
				d = d - 0.01
			else
				b = b - 0.01
			end
		elseif char.name == "right" then
			if tab.contains(modifiers, "shift") then
				d = d + 0.01
			else
				b = b + 0.01
			end
		end
	end
end

function color(x, y)
	local r = util.linlin(0, 15, 0, 255, p[y * 16 + x])
	local g = util.linlin(0, 15, 0, 255, p[y * 16 + y])
	local b = util.linlin(0, 15, 0, 255, p[x * 16 + y])
	return r, g, b
end

function redraw()
	screen.clear()
	for x = 1, 16 do
		for y = 1, 16 do
			screen.color(color(x, y))
			screen.pixel((x - 1) * 4, (y - 1) * 4)
		end
	end
	screen.color(255, 255, 255)
	screen.move(120, 10)
	screen.text("t")
	screen.move(115, 10)
	screen.text_right(time)
	screen.move(120, 20)
	screen.text("f")
	screen.move(115, 20)
	screen.text_right(f)
	screen.move(120, 30)
	screen.text("a")
	screen.move(115, 30)
	screen.text_right(a)
	screen.move(120, 40)
	screen.text("b")
	screen.move(115, 40)
	screen.text_right(b)
	screen.move(120, 50)
	screen.text("c")
	screen.move(115, 50)
	screen.text_right(c)
	screen.move(120, 60)
	screen.text("d")
	screen.move(115, 60)
	screen.text_right(d)
	screen.refresh()
end
