--- hello_triangle.lua
-- simply draws and rotates a colorful triangle to the screen.

-- seamstress calls init() when it's ready to start your script!
function init()
	-- this controls the speed of the rotation!
	-- give it a change and see what happens.
	FRAMES = 120
	-- clear the screen to make sure it doesn't have weird gunk
	screen.clear()
	-- defines a triangular mesh.
	-- since we only give it one argument,
	-- it will attempt to draw triangles
	-- by taking the vertices in order as we've written them.
	-- since there are three, we get one triangle.
	-- the vertices argument is a list.
	-- each list element is a list;
	-- they go 1) pixel coordinates
	-- 2) color data
	-- and optionally 3) texture coordinates.
	-- here we're skipping the texture coordinates.
	-- our triangle has three vertices
	-- and we're coloring them full red, full green and full blue, respectively.
	screen.geometry({
		{ { 10, 10 }, { 255, 0, 0 } },
		{ { 100, 10 }, { 0, 255, 0 } },
		{ { 10, 100 }, { 0, 0, 255 } },
	})
	-- think of this like saving a screenshot
	Texture = screen.new_texture(110, 110)
	-- we don't actually want to draw *this* triangle, so let's clear the screen
	screen.clear()

	-- let's set up our rendering function.
	-- we could use metros instead, but let's do clocks here.
	Clock = clock.run(function()
		local frame = 0
		-- if you want a clock function to run until canceled, you need a while true!
		while true do
			-- convert our frame number into an angle
			local theta = frame * 2 * math.pi / FRAMES
			-- no gunk!
			screen.clear()
			-- the arguments are x-coordinate, y-coordinate,
			-- an angle to rotate by,
			-- whether to flip horizontally,
			-- whether to flip vertically,
			-- and finally a zoom parameter.
			-- actually many of these are optional, but let's give them all.
			-- screen.width and screen.height are useful because
			-- the user can resize the seamstress window!
			Texture:render_extended(screen.width / 2 - 50, screen.height / 2 - 50, theta, false, false, 1)
			-- this actually shows us what we've drawn to the screen
			screen.refresh()
			-- this advances the current frame by 1,
			-- wrapping so that if we're equal to FRAMES, the next frame number is 1
			frame = frame % FRAMES + 1
			-- gotta make sure we're sleeping!
			-- this effectively sets our FPS to 60
			clock.sleep(1 / 60)
		end
	end)
end
