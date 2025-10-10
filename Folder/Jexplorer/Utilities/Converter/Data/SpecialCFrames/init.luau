local CFRAMES = {
	-- Identity and cardinal directions
	CFrame.Angles(0, 0, 0),
	CFrame.Angles(0, math.rad(180), 0),
	CFrame.Angles(math.rad(90), 0, 0),
	CFrame.Angles(math.rad(-90), 0, 0),
	CFrame.Angles(0, 0, math.rad(90)),
	CFrame.Angles(0, 0, math.rad(-90)),
	CFrame.Angles(0, math.rad(90), 0),
	CFrame.Angles(0, math.rad(-90), 0),
	CFrame.Angles(0, math.rad(180), math.rad(180)),
	CFrame.Angles(0, 0, math.rad(180)),

	-- Combined rotations
	--CFrame.Angles(math.rad(-90), math.rad(-180), 0),
	--CFrame.Angles(math.rad(90), math.rad(180), 0),
	--CFrame.Angles(0, math.rad(180), math.rad(90)),
	--CFrame.Angles(0, math.rad(90), math.rad(90)),
	--CFrame.Angles(0, math.rad(-90), math.rad(-90)),
	--CFrame.Angles(0, math.rad(-180), math.rad(-90)),
	--CFrame.Angles(0, math.rad(-90), math.rad(90)),
	--CFrame.Angles(0, math.rad(90), math.rad(-90)),
	--CFrame.Angles(math.rad(-90), math.rad(-90), 0),
	--CFrame.Angles(math.rad(90), math.rad(90), 0),
	--CFrame.Angles(math.rad(90), math.rad(-90), 0),
	--CFrame.Angles(math.rad(-90), math.rad(90), 0),
	--CFrame.Angles(0, math.rad(90), math.rad(180)),
	--CFrame.Angles(0, math.rad(-90), math.rad(180)),

	---- 45-degree rotations
	--CFrame.Angles(math.rad(90), math.rad(45), 0),
	--CFrame.Angles(math.rad(90), math.rad(-45), 0),
	--CFrame.Angles(math.rad(-90), math.rad(45), 0),
	--CFrame.Angles(math.rad(-90), math.rad(-45), 0),
	--CFrame.Angles(math.rad(45), 0, 0),
	--CFrame.Angles(math.rad(-45), 0, 0),
	--CFrame.Angles(0, math.rad(45), 0),
	--CFrame.Angles(0, math.rad(-45), 0),
	--CFrame.Angles(0, 0, math.rad(45)),
	--CFrame.Angles(0, 0, math.rad(-45)),
	--CFrame.Angles(math.rad(45), math.rad(45), 0),
	--CFrame.Angles(math.rad(45), math.rad(-45), 0),
	--CFrame.Angles(0, math.rad(45), math.rad(45)),
	--CFrame.Angles(0, math.rad(-45), math.rad(45)),
	--CFrame.Angles(math.rad(45), 0, math.rad(45)),
	--CFrame.Angles(math.rad(-45), 0, math.rad(45)),
	
	--CFrame.Angles(math.rad(45), math.rad(90), 0),
	--CFrame.Angles(math.rad(45), math.rad(-90), 0),
	--CFrame.Angles(math.rad(-45), math.rad(90), 0),
	--CFrame.Angles(math.rad(-45), math.rad(-90), 0),
	--CFrame.Angles(math.rad(90), math.rad(90), math.rad(45)),
	--CFrame.Angles(math.rad(90), math.rad(-90), math.rad(45)),
	--CFrame.Angles(math.rad(-90), math.rad(90), math.rad(45)),
	--CFrame.Angles(math.rad(-90), math.rad(-90), math.rad(45)),
	--CFrame.Angles(math.rad(45), math.rad(45), math.rad(45)),
	--CFrame.Angles(math.rad(45), math.rad(45), math.rad(-45)),
	--CFrame.Angles(math.rad(45), math.rad(-45), math.rad(45)),
	--CFrame.Angles(math.rad(45), math.rad(-45), math.rad(-45)),
	--CFrame.Angles(math.rad(-45), math.rad(45), math.rad(45)),
	--CFrame.Angles(math.rad(-45), math.rad(45), math.rad(-45)),
	--CFrame.Angles(math.rad(-45), math.rad(-45), math.rad(45)),
	--CFrame.Angles(math.rad(-45), math.rad(-45), math.rad(-45)),

	---- 30/60 degree rotations
	--CFrame.Angles(math.rad(30), 0, 0),
	--CFrame.Angles(math.rad(-30), 0, 0),
	--CFrame.Angles(0, math.rad(30), 0),
	--CFrame.Angles(0, math.rad(-30), 0),
	--CFrame.Angles(0, 0, math.rad(30)),
	--CFrame.Angles(0, 0, math.rad(-30)),
	--CFrame.Angles(math.rad(60), 0, 0),
	--CFrame.Angles(math.rad(-60), 0, 0),
	--CFrame.Angles(0, math.rad(60), 0),
	--CFrame.Angles(0, math.rad(-60), 0),
	--CFrame.Angles(0, 0, math.rad(60)),
	--CFrame.Angles(0, 0, math.rad(-60)),
	
	--CFrame.Angles(math.rad(30), math.rad(30), 0),
	--CFrame.Angles(math.rad(60), math.rad(60), 0),
	--CFrame.Angles(0, math.rad(30), math.rad(30)),
	--CFrame.Angles(0, math.rad(60), math.rad(60)),
	--CFrame.Angles(math.rad(30), 0, math.rad(30)),
	--CFrame.Angles(math.rad(60), 0, math.rad(60)),
	--CFrame.Angles(math.rad(90), math.rad(30), 0),
	--CFrame.Angles(math.rad(90), math.rad(60), 0),
	--CFrame.Angles(math.rad(30), math.rad(90), 0),
	--CFrame.Angles(math.rad(60), math.rad(90), 0),
	--CFrame.Angles(math.rad(30), math.rad(60), math.rad(90)),

	---- 120/135/150 degree rotations
	--CFrame.Angles(math.rad(120), 0, 0),
	--CFrame.Angles(0, math.rad(120), 0),
	--CFrame.Angles(0, 0, math.rad(120)),
	--CFrame.Angles(math.rad(135), 0, 0),
	--CFrame.Angles(0, math.rad(135), 0),
	--CFrame.Angles(0, 0, math.rad(135)),
	--CFrame.Angles(math.rad(150), 0, 0),
	--CFrame.Angles(0, math.rad(150), 0),
	--CFrame.Angles(0, 0, math.rad(150)),
}

--for i = 1, 360 do
--	local x = CFrame.Angles(math.rad(i), 0, 0)
--	local y = CFrame.Angles(0, math.rad(i), 0)
--	local z = CFrame.Angles(0, 0, math.rad(i))
	
--	local nx = CFrame.Angles(-math.rad(i), 0, 0)
--	local ny = CFrame.Angles(0, -math.rad(i), 0)
--	local nz = CFrame.Angles(0, 0, -math.rad(i))
	
--	if not table.find(CFRAMES, x) then
--		table.insert(CFRAMES, x)
--	end
--	if not table.find(CFRAMES, y) then
--		table.insert(CFRAMES, y)
--	end
--	if not table.find(CFRAMES, z) then
--		table.insert(CFRAMES, z)
--	end
--	if not table.find(CFRAMES, nx) then
--		table.insert(CFRAMES, nx)
--	end
--	if not table.find(CFRAMES, ny) then
--		table.insert(CFRAMES, ny)
--	end
--	if not table.find(CFRAMES, nz) then
--		table.insert(CFRAMES, nz)
--	end
--end

return CFRAMES