-- hello_psets.lua
-- introduces how to save preset files (known as PSETs)

-- presets collect PARAMETER values for easy recall of desired script states.
-- files are saved to your seamstress path, under 'data/<scriptname>/<scriptname-PSETnumber>.pset'

-- toggle the PSET menu with SHIFT + P:
--    use the left and right arrow keys to switch between SAVE, LOAD, and DELETE.
--    use the up and down arrow keys to navigate the PSET list -- hold ALT to jump by 8 slots.

-- SAVING:
-- when SAVE is highlighted, press ENTER on any PSET slot to open a text field for naming it:
--    ESCAPE cancels the write, leaving the slot untouched
--    ENTER commits the write
-- scripting:
--    you can use params:write(number, string) to commit a preset to slot number using string name.
--    you can also specify params.action_write(filename, name, number) as a callback to this action
--      in your script's init().

-- LOADING:
-- when LOAD is highlighted, press ENTER on any PSET slot to load it:
--    on successful read, pset >> read: <path_to_file>.pset will print to the console
-- scripting:
--    params:read() to read the last loaded PSET
--    params:read(number) to read the PSET at slot number
--    params:read(filepath) to read the PSET at a specific filepath
--    you can also specify params.action_read(filename, name, number, silent) as a callback to this action
--      in your script's init().

-- DELETING:
-- when DELETE is highlighted, press ENTER on any PSET slot to queue it for deletion,
--    which requires another ENTER for secondary confirmation.
-- scripting:
--    params:delete(number) to delete the PSET at slot number
--    params:delete(filepath) to delete the PSET at a specific filepath
--    you can also specify params.action_delete(filename, name, number) as a callback to this action
--      in your script's init().

saved_filepath = ""
saved_name = ""
saved_number = ""
display_string = {}

function init()
	header = function(text)
		screen.color(255, 160, 122)
		screen.text(text)
	end

	instruction = function(text)
		screen.color(154, 205, 50)
		screen.text(text)
	end

	params:add_separator("hello PSETs!")
	params:add_group("a few related parameters", 4)
	for i = 1, 4 do
		params:add_number("number_" .. i, "example " .. i, 0, 127, 63)
	end

	scrolling_display_clock = clock.run(function()
		while true do
			redraw()
			clock.sleep(1 / 6)
		end
	end)

	params.action_write = function(filename, name, number)
		saved_filepath = filename
		saved_name = name
		saved_number = number
		display_string = {}
		redraw()
	end
end

function scroll_text(text, space, interval)
	-- adapted from https://watchmakertips.blogspot.com/2019/01/this-script-will-scroll-text.html
	display_string[text] = display_string[text] or 0
	display_string[text] = display_string[text] + 1

	if not interval then
		interval = 1
	end

	local length = string.len(text)

	-- dont scroll
	if length <= space then
		return text
	end

	local running_time = display_string[text]
	local starting = (running_time % (length / interval)) * interval
	local ending = starting + space

	local return_text = string.sub(text, starting, ending)

	return return_text
end

function redraw()
	screen.clear()
	screen.move(10, 10)
	header("in params window:")
	screen.move(20, 20)
	instruction("SHIFT + P: toggle PSET menu")
	screen.move(20, 30)
	instruction("U/D: navigate PSET slots")
	screen.move(20, 40)
	instruction("L/R: switch between actions (SAVE / LOAD / DELETE)")
	screen.move(20, 50)
	instruction("ENTER / RETURN: perform action on slot")

	screen.move(10, 65)
	header("after save, these will auto-fill:")
	screen.move(20, 75)
	instruction("filepath: " .. scroll_text(saved_filepath, 35, 1))
	screen.move(20, 85)
	instruction("saved name: " .. saved_name)
	screen.move(20, 95)
	instruction("saved slot number: " .. saved_number)

	screen.refresh()
end