--!strict
-- The picture for a staged scene (a LoreText scene with a `stage`): a small set cut from blocks,
-- lit by a ViewportFrame's own ambient light so the dark world is never touched, with a
-- camera that moves and a blocky figure who bobs their head while they speak. Cutscene.luau
-- opens a stage, calls Stage.run(name) at each `stage` beat, and Stage.speak when a line starts.
--
-- Two sets:
--   office  the opening: a condemned office floor, Theo's scanner sweeping red dots over it,
--           Theo leaning on a wall that melts, black, then a low look at the melted wall.
--   tape    a videotape: one figure at a desk under a banker's lamp, in front of a map.
--
-- Every function is safe to call at any time; a mistake here must never stop a cutscene.

local RunService = game:GetService("RunService")

local Stage = {}

type Figure = { parts: { [string]: Part }, color: Color3 }

local SKIN = Color3.fromRGB(222, 184, 150)
local FIGURE_COLORS: { [string]: Color3 } = {
	Theo = Color3.fromRGB(214, 124, 46),
	Ines = Color3.fromRGB(60, 112, 82),
	Pike = Color3.fromRGB(124, 92, 60),
	Hollis = Color3.fromRGB(110, 114, 132),
	Tobi = Color3.fromRGB(128, 62, 62),
	Ravi = Color3.fromRGB(60, 92, 142),
	Quill = Color3.fromRGB(94, 72, 114),
	Echo = Color3.fromRGB(226, 226, 236),
	Announcer = Color3.fromRGB(124, 92, 60),
}
local DEFAULT_FIGURE = Color3.fromRGB(110, 110, 110)
local WALLPAPER = Color3.fromRGB(176, 156, 88)
local MELTED = Color3.fromRGB(214, 176, 74)
local OFFICE_AMBIENT = Color3.fromRGB(168, 164, 150)
local OFFICE_LIGHT = Color3.fromRGB(220, 214, 196)
local DOT_COLOR = Color3.fromRGB(255, 70, 60)
local DOT_COUNT = 520
local DOT_GAP = 0.028
local ARM_FORWARD = math.pi / 2 -- a hanging arm swung to point the way the figure faces

local viewport: ViewportFrame? = nil
local camera: Camera? = nil
local stepConnection: RBXScriptConnection? = nil
local token = 0 -- bumps at every cut; running animations stop when theirs is stale
local dotsToken = 0 -- the same for the dots that build up over the office
local setName = ""

local camFrom = CFrame.new()
local camTo = CFrame.new()
local camStart = 0
local camSeconds = 1
local camRoll = 0

local figure: Figure? = nil
local figureRoot = CFrame.new()
local armAngle = 0
local talkUntil = 0
local ceilingLights: { Part } = {}
local extra: Figure? = nil -- Echo, or the shape in Quill's corridor
local extraRoot = CFrame.new()
local extraTalk = 0
local shapeStep = 0
local fadeGoal = 0 -- how far the speaker has faded from the picture, 0 to 1
local fadeNow = 0
local drips: { Part } = {}
local doorLight: Part? = nil
local sceneId = ""
local melt: { panel: Part?, glow: Part?, drips: { Part }, progress: number } =
	{ panel = nil, glow = nil, drips = {}, progress = 0 }

local function newPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = viewport
	return part
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- Moves the camera from where it is to a new shot over `seconds`, easing in and out.
local function aim(from: Vector3, lookAt: Vector3, to: Vector3, lookAtEnd: Vector3, seconds: number)
	camFrom = CFrame.lookAt(from, lookAt)
	camTo = CFrame.lookAt(to, lookAtEnd)
	camStart = os.clock()
	camSeconds = math.max(seconds, 0.05)
end

local function lighting(ambient: Color3, light: Color3)
	local frame = viewport
	if frame then
		frame.Ambient = ambient
		frame.LightColor = light
		frame.LightDirection = Vector3.new(-0.3, -1, -0.4)
	end
end

--------------------------------------------------------------------------------------------
-- Figures

local function newFigure(color: Color3): Figure
	local parts: { [string]: Part } = {}
	parts.Head =
		newPart("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(), SKIN, nil, Enum.PartType.Ball)
	parts.Torso = newPart("Torso", Vector3.new(1.8, 2, 0.9), CFrame.new(), color)
	parts.ArmL = newPart("ArmL", Vector3.new(0.7, 1.9, 0.7), CFrame.new(), color)
	parts.ArmR = newPart("ArmR", Vector3.new(0.7, 1.9, 0.7), CFrame.new(), color)
	parts.LegL = newPart("LegL", Vector3.new(0.8, 2, 0.8), CFrame.new(), Color3.fromRGB(46, 48, 58))
	parts.LegR = newPart("LegR", Vector3.new(0.8, 2, 0.8), CFrame.new(), Color3.fromRGB(46, 48, 58))
	return { parts = parts, color = color }
end

local function recolor(who: Figure, color: Color3)
	who.color = color
	for _, name in { "Torso", "ArmL", "ArmR" } do
		who.parts[name].Color = color
	end
end

-- Sets every part of a figure from a root (the feet, facing along the root's look vector).
local function pose(who: Figure, root: CFrame, right: number, left: number, bob: number)
	local parts = who.parts
	parts.Torso.CFrame = root * CFrame.new(0, 3, 0)
	parts.Head.CFrame = root * CFrame.new(0, 4.5 + bob, 0)
	parts.LegL.CFrame = root * CFrame.new(-0.45, 1, 0)
	parts.LegR.CFrame = root * CFrame.new(0.45, 1, 0)
	parts.ArmR.CFrame = root
		* CFrame.new(1.25, 3.95, 0)
		* CFrame.Angles(right, 0, 0)
		* CFrame.new(0, -0.95, 0)
	parts.ArmL.CFrame = root
		* CFrame.new(-1.25, 3.95, 0)
		* CFrame.Angles(left, 0, 0)
		* CFrame.new(0, -0.95, 0)
end

local function showFigure(who: Figure, visible: boolean)
	for _, part in who.parts do
		part.Transparency = if visible then 0 else 1
	end
end

--------------------------------------------------------------------------------------------
-- The office

local function buildOffice()
	local floorColor = Color3.fromRGB(108, 102, 88)
	newPart("Floor", Vector3.new(40, 1, 70), CFrame.new(0, -0.5, 0), floorColor)
	newPart("WallBack", Vector3.new(40, 14, 1), CFrame.new(0, 7, -26), WALLPAPER)
	newPart("WallL", Vector3.new(1, 14, 70), CFrame.new(-20, 7, 0), WALLPAPER)
	newPart("WallR", Vector3.new(1, 14, 70), CFrame.new(20, 7, 0), WALLPAPER)
	newPart("Pillar", Vector3.new(2, 14, 2), CFrame.new(-15, 7, 0), Color3.fromRGB(150, 134, 80))
	newPart("Pillar", Vector3.new(2, 14, 2), CFrame.new(8, 7, -12), Color3.fromRGB(150, 134, 80))
	newPart("Desk", Vector3.new(6, 3, 3), CFrame.new(-13, 1.5, -6), Color3.fromRGB(96, 82, 62))
	newPart("Desk", Vector3.new(6, 3, 3), CFrame.new(12, 1.5, 4), Color3.fromRGB(96, 82, 62))
	newPart("Chair", Vector3.new(2, 2.4, 2), CFrame.new(-13, 1.2, -3), Color3.fromRGB(50, 52, 58))
	for index, z in { 14, 2, -10, -22 } do
		local lamp = newPart(
			"Ceiling" .. index,
			Vector3.new(6, 0.2, 2),
			CFrame.new(0, 13.4, z),
			Color3.fromRGB(236, 255, 226),
			Enum.Material.Neon
		)
		table.insert(ceilingLights, lamp)
	end

	-- The tripod and scanner.
	local base = Vector3.new(6, 0, -6)
	for _, angle in { 0, 120, 240 } do
		local direction = CFrame.Angles(0, math.rad(angle), 0).LookVector
		local foot = base + direction * 1.4
		newPart(
			"TripodLeg",
			Vector3.new(0.18, 3.8, 0.18),
			CFrame.lookAt((foot + base + Vector3.new(0, 3.6, 0)) / 2, base + Vector3.new(0, 3.6, 0))
				* CFrame.Angles(math.pi / 2, 0, 0),
			Color3.fromRGB(40, 40, 44)
		)
	end
	newPart(
		"ScannerHead",
		Vector3.new(1.3, 1.1, 1.3),
		CFrame.new(base + Vector3.new(0, 4.2, 0)),
		Color3.fromRGB(70, 74, 80)
	)
	newPart(
		"ScannerLens",
		Vector3.new(0.5, 0.5, 0.3),
		CFrame.new(base + Vector3.new(0, 4.2, -0.7)),
		DOT_COLOR,
		Enum.Material.Neon
	)

	-- The wall that will melt: a panel set into the back wall, and the drips that will run.
	melt.panel =
		newPart("MeltPanel", Vector3.new(9, 10, 0.6), CFrame.new(-2, 5.2, -25.4), WALLPAPER)
	local glow = newPart(
		"MeltGlow",
		Vector3.new(8, 9.4, 0.2),
		CFrame.new(-2, 4.9, -26.1),
		Color3.fromRGB(255, 226, 150),
		Enum.Material.Neon
	)
	glow.Transparency = 1
	melt.glow = glow
	melt.drips = {}
	for index, x in { -5.4, -4, -2.6, -1.2, 0.2, 1.4, 2.6 } do
		local drip = newPart(
			"Drip",
			Vector3.new(0.1, 0.8 + (index % 3) * 0.2, 0.8 + (index % 3) * 0.2),
			CFrame.new(x, 9.8, -25) * CFrame.Angles(0, 0, math.rad(90)),
			MELTED,
			nil,
			Enum.PartType.Cylinder
		)
		drip.Transparency = 1
		table.insert(melt.drips, drip)
	end
	melt.progress = 0
end

-- 0 is wallpaper, 1 is run like wax: the panel warms, the drips lengthen and reach the floor.
local function setMelt(progress: number)
	melt.progress = progress
	local panel = melt.panel
	if panel then
		panel.Color = lerpColor(WALLPAPER, MELTED, progress)
		panel.Transparency = 0.5 * progress
	end
	local glow = melt.glow
	if glow then
		glow.Transparency = 1 - 0.85 * progress -- a warm light behind it: a way through
	end
	for index, drip in melt.drips do
		local reach = progress * (6.4 + (index % 3) * 1.4)
		drip.Transparency = if progress <= 0.02 then 1 else 0
		drip.Size = Vector3.new(math.max(reach, 0.1), drip.Size.Y, drip.Size.Z)
		drip.CFrame = CFrame.new(drip.Position.X, 9.8 - reach / 2, -25)
			* CFrame.Angles(0, 0, math.rad(90))
	end
end

local function scatterDots(myToken: number)
	local used = 0
	while dotsToken == myToken and used < DOT_COUNT and viewport ~= nil do
		used += 1
		local roll = math.random()
		local position: Vector3
		if roll < 0.4 then
			position =
				Vector3.new(math.random(-19, 19) + math.random(), math.random() * 13 + 0.3, -25.45)
		elseif roll < 0.6 then
			position =
				Vector3.new(-19.45, math.random() * 13 + 0.3, math.random(-24, 30) + math.random())
		elseif roll < 0.8 then
			position =
				Vector3.new(19.45, math.random() * 13 + 0.3, math.random(-24, 30) + math.random())
		else
			position = Vector3.new(
				math.random(-19, 19) + math.random(),
				0.05,
				math.random(-24, 30) + math.random()
			)
		end
		newPart(
			"Dot",
			Vector3.new(0.3, 0.3, 0.3),
			CFrame.new(position),
			DOT_COLOR,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		task.wait(DOT_GAP)
	end
end

local function clearTransients()
	local frame = viewport
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if child.Name == "Dot" then
			child:Destroy()
		end
	end
end

local function runOffice(name: string)
	if name == "office" then
		token += 1
		dotsToken += 1
		local myToken = dotsToken
		lighting(OFFICE_AMBIENT, OFFICE_LIGHT)
		setMelt(0)
		local who = figure
		if who then
			figureRoot = CFrame.lookAt(Vector3.new(3, 0, -4), Vector3.new(6, 0, -6))
			armAngle = 0
			pose(who, figureRoot, 0, 0, 0)
			showFigure(who, true)
		end
		aim(
			Vector3.new(-15, 6, 17),
			Vector3.new(4, 4, -8),
			Vector3.new(-6, 5, 8),
			Vector3.new(3, 4, -10),
			16
		)
		task.spawn(scatterDots, myToken)
	elseif name == "lean" then
		token += 1
		local myToken = token
		local who = figure
		if who == nil then
			return
		end
		local start = figureRoot.Position
		local startPosition = if camera then camera.CFrame.Position else camTo.Position
		local target = Vector3.new(-2, 0, -22.8)
		aim(
			startPosition,
			Vector3.new(0, 4, -8),
			Vector3.new(7, 4.5, -11),
			Vector3.new(-2, 4, -23),
			3.4
		)
		task.spawn(function()
			local walkSeconds = 2.8
			local began = os.clock()
			while token == myToken do
				local alpha = math.clamp((os.clock() - began) / walkSeconds, 0, 1)
				local position = start:Lerp(target, alpha)
				figureRoot = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
				if alpha >= 1 then
					break
				end
				task.wait()
			end
			-- Raise the hand to the wall.
			began = os.clock()
			while token == myToken do
				local alpha = math.clamp((os.clock() - began) / 0.6, 0, 1)
				armAngle = ARM_FORWARD * alpha
				if alpha >= 1 then
					break
				end
				task.wait()
			end
			-- The wall gives: it melts and the hand sinks in.
			began = os.clock()
			while token == myToken do
				local alpha = math.clamp((os.clock() - began) / 2.2, 0, 1)
				setMelt(alpha)
				local position = target + Vector3.new(0, 0, -0.9 * alpha)
				figureRoot = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
				if alpha >= 1 then
					break
				end
				task.wait()
			end
			-- The lights go, one stutter at a time.
			for step = 1, 7 do
				if token ~= myToken then
					return
				end
				local on = step % 2 == 0
				for _, lamp in ceilingLights do
					lamp.Transparency = if on then 0 else 1
				end
				lighting(
					if on then OFFICE_AMBIENT else Color3.fromRGB(8, 8, 10),
					if on then OFFICE_LIGHT else Color3.fromRGB(10, 10, 12)
				)
				task.wait(0.09 + 0.05 * (step % 3))
			end
		end)
	elseif name == "dark" then
		token += 1
		if viewport then
			viewport.Visible = false
		end
	elseif name == "wake" then
		token += 1
		clearTransients()
		local who = figure
		if who then
			showFigure(who, false)
		end
		setMelt(1)
		for _, lamp in ceilingLights do
			lamp.Transparency = 1
		end
		lighting(Color3.fromRGB(176, 140, 84), Color3.fromRGB(255, 214, 140))
		if viewport then
			viewport.Visible = true
		end
		aim(
			Vector3.new(-2, 1.3, -16),
			Vector3.new(-2, 3, -24.6),
			Vector3.new(-2, 3.4, -15),
			Vector3.new(-2, 7.5, -24.6),
			9
		)
	end
end

--------------------------------------------------------------------------------------------
-- The tape
--
-- Seven tapes, each in a room of its own: the colours, the props and a few cues (`@fade`,
-- `@echo`, `@shape`...) tell what the words only say. The room is picked by the scene id.

type Look = { wall: Color3, floor: Color3, ambient: Color3, light: Color3 }
type Block = { size: Vector3, at: Vector3, color: Color3, neon: boolean? }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local TAPE_LOOKS: { [string]: Look } = {
	["tape.orientation"] = {
		wall = rgb(104, 124, 112),
		floor = rgb(78, 86, 80),
		ambient = rgb(172, 180, 168),
		light = rgb(230, 214, 170),
	},
	["tape.halden"] = {
		wall = rgb(120, 176, 214),
		floor = rgb(226, 220, 206),
		ambient = rgb(205, 205, 210),
		light = rgb(255, 250, 236),
	},
	["tape.hollis"] = {
		wall = rgb(118, 120, 126),
		floor = rgb(92, 94, 98),
		ambient = rgb(158, 160, 166),
		light = rgb(200, 204, 214),
	},
	["tape.tobi"] = {
		wall = rgb(66, 110, 114),
		floor = rgb(50, 76, 80),
		ambient = rgb(138, 172, 178),
		light = rgb(170, 220, 226),
	},
	["tape.ravi"] = {
		wall = rgb(160, 182, 160),
		floor = rgb(124, 136, 122),
		ambient = rgb(182, 192, 182),
		light = rgb(230, 238, 220),
	},
	["tape.quill"] = {
		wall = rgb(96, 80, 68),
		floor = rgb(70, 60, 52),
		ambient = rgb(150, 134, 122),
		light = rgb(240, 208, 156),
	},
	["tape.pike"] = {
		wall = rgb(122, 100, 64),
		floor = rgb(76, 68, 56),
		ambient = rgb(190, 156, 96),
		light = rgb(255, 196, 110),
	},
}

local function blocks(list: { Block })
	for _, block in list do
		local material = if block.neon then Enum.Material.Neon else nil
		newPart("Prop", block.size, CFrame.new(block.at), block.color, material)
	end
end

local function lampOn(at: Vector3)
	newPart("LampBase", Vector3.new(0.9, 0.3, 0.9), CFrame.new(at), Color3.fromRGB(40, 70, 52))
	newPart(
		"LampStem",
		Vector3.new(0.2, 1.6, 0.2),
		CFrame.new(at + Vector3.new(0, 0.85, 0)),
		Color3.fromRGB(40, 70, 52)
	)
	newPart(
		"LampShade",
		Vector3.new(0.6, 1.6, 1.6),
		CFrame.new(at + Vector3.new(0, 1.75, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(34, 96, 66),
		nil,
		Enum.PartType.Cylinder
	)
	newPart(
		"LampBulb",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(at + Vector3.new(0, 1.35, 0)),
		Color3.fromRGB(255, 232, 160),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
end

local function table3(at: Vector3, width: number, color: Color3)
	newPart("Table", Vector3.new(width, 3, 3.6), CFrame.new(at + Vector3.new(0, 1.5, 0)), color)
end

local function buildTape(id: string)
	local look = TAPE_LOOKS[id] or TAPE_LOOKS["tape.orientation"]
	newPart("Floor", Vector3.new(60, 1, 44), CFrame.new(0, -0.5, 0), look.floor)
	newPart("WallBack", Vector3.new(60, 16, 1), CFrame.new(0, 8, -12), look.wall)
	newPart("WallL", Vector3.new(1, 16, 44), CFrame.new(-16, 8, 0), look.wall)
	newPart("WallR", Vector3.new(1, 16, 44), CFrame.new(16, 8, 0), look.wall)
	local wood = rgb(120, 92, 62)
	if id == "tape.orientation" then
		-- Ines's office: wall maps with the routes drawn in red, a desk, the banker's lamp.
		newPart("Map", Vector3.new(13, 8, 0.3), CFrame.new(0, 7.5, -11.4), rgb(226, 218, 186))
		newPart("Map", Vector3.new(7, 6, 0.3), CFrame.new(-11, 7, -11.4), rgb(212, 204, 176))
		for index = 1, 7 do
			newPart(
				"MapLine",
				Vector3.new(2 + (index % 3) * 2.2, 0.14, 0.2),
				CFrame.new(-3 + (index % 4) * 1.8, 4.8 + index * 0.8, -11.2)
					* CFrame.Angles(0, 0, math.rad(index * 11 - 30)),
				rgb(176, 52, 44)
			)
		end
		table3(Vector3.new(0, 0, -3.5), 9, wood)
		lampOn(Vector3.new(3.4, 3, -3.2))
		newPart("Papers", Vector3.new(1.8, 0.1, 1.3), CFrame.new(-2.4, 3.1, -3), rgb(236, 230, 210))
	elseif id == "tape.halden" then
		-- The lobby, 1994: marble, glass, a fountain, a ribbon, and a door that is not on the plan.
		blocks({
			{
				size = Vector3.new(7, 1.2, 7),
				at = Vector3.new(7, 0.6, -3),
				color = rgb(200, 200, 206),
			},
			{
				size = Vector3.new(4, 1, 4),
				at = Vector3.new(7, 1.6, -3),
				color = rgb(160, 210, 255),
			},
			{
				size = Vector3.new(1, 5, 1),
				at = Vector3.new(7, 3.8, -3),
				color = rgb(190, 235, 255),
				neon = true,
			},
			{
				size = Vector3.new(14, 0.5, 0.2),
				at = Vector3.new(-2, 3.4, 3),
				color = rgb(220, 40, 50),
			},
			{
				size = Vector3.new(0.3, 4, 0.3),
				at = Vector3.new(-9, 2, 3),
				color = rgb(210, 210, 214),
			},
			{
				size = Vector3.new(0.3, 4, 0.3),
				at = Vector3.new(5, 2, 3),
				color = rgb(210, 210, 214),
			},
			{
				size = Vector3.new(16, 3, 0.3),
				at = Vector3.new(-9, 12, -11.4),
				color = rgb(255, 214, 90),
			},
		})
		local door = newPart(
			"Door",
			Vector3.new(3, 7, 0.4),
			CFrame.new(-10, 3.5, -11.5),
			rgb(255, 226, 150),
			Enum.Material.Neon
		)
		door.Transparency = 1
		doorLight = door
	elseif id == "tape.hollis" then
		-- A security camera's view: grey doors down a corridor, a wet carpet.
		for index, x in { -12, -8, -4, 4, 8, 12 } do
			blocks({
				{
					size = Vector3.new(2.6, 6.4, 0.3),
					at = Vector3.new(x, 3.2, -11.4),
					color = rgb(70 + index * 3, 72, 78),
				},
			})
		end
		blocks({
			{
				size = Vector3.new(60, 0.1, 6),
				at = Vector3.new(0, 0.05, -6),
				color = rgb(70, 80, 90),
			},
		})
		for _, x in { -10, 0, 10 } do
			newPart(
				"Ceiling",
				Vector3.new(4, 0.2, 1.2),
				CFrame.new(x, 14, -4),
				rgb(230, 240, 255),
				Enum.Material.Neon
			)
		end
	elseif id == "tape.tobi" then
		-- The pump room: pipes along the wall, a shelf, the cassette player, water dripping.
		for index, y in { 4, 7, 10 } do
			newPart(
				"Pipe",
				Vector3.new(60, 0.9, 0.9),
				CFrame.new(0, y, -11),
				rgb(120 + index * 10, 140, 130),
				Enum.Material.Metal,
				Enum.PartType.Cylinder
			)
		end
		blocks({
			{ size = Vector3.new(6, 0.3, 2), at = Vector3.new(-5, 3, -3.4), color = wood },
			{
				size = Vector3.new(1.8, 1, 0.9),
				at = Vector3.new(-5, 3.7, -3.4),
				color = rgb(30, 32, 36),
			},
			{
				size = Vector3.new(0.25, 0.25, 0.1),
				at = Vector3.new(-4.4, 3.9, -2.9),
				color = rgb(255, 60, 50),
				neon = true,
			},
			{
				size = Vector3.new(6, 0.12, 6),
				at = Vector3.new(6, 0.06, -4),
				color = rgb(90, 160, 190),
			},
		})
		for index = 1, 5 do
			local drop = newPart(
				"Drip",
				Vector3.new(0.3, 0.45, 0.3),
				CFrame.new(5 + index * 0.8, 9, -4 + (index % 3)),
				rgb(170, 225, 255),
				Enum.Material.Neon,
				Enum.PartType.Ball
			)
			table.insert(drips, drop)
		end
	elseif id == "tape.ravi" then
		-- The day room: a ward curtain, a radio on the table, an empty bed.
		for index = 0, 9 do
			newPart(
				"Curtain",
				Vector3.new(1.4, 10, 0.4),
				CFrame.new(-12 + index * 1.35, 5.5, -11.2),
				rgb(110 + (index % 2) * 14, 150, 190)
			)
		end
		table3(Vector3.new(0, 0, -3.5), 7, rgb(190, 176, 150))
		blocks({
			{
				size = Vector3.new(1.8, 1, 0.8),
				at = Vector3.new(2.4, 3.5, -3.4),
				color = rgb(60, 52, 44),
			},
			{
				size = Vector3.new(0.3, 0.3, 0.1),
				at = Vector3.new(2.7, 3.6, -2.95),
				color = rgb(255, 190, 70),
				neon = true,
			},
			{
				size = Vector3.new(6, 1.4, 3),
				at = Vector3.new(11, 0.9, -7),
				color = rgb(228, 232, 236),
			},
			{
				size = Vector3.new(0.4, 3, 3),
				at = Vector3.new(14, 1.5, -7),
				color = rgb(150, 154, 160),
			},
		})
	elseif id == "tape.quill" then
		-- A cave wall, a slide projector and the picture it throws: a corridor, and a shape in it.
		for index = 1, 9 do
			newPart(
				"Rock",
				Vector3.new(3 + (index % 3) * 2, 3 + (index % 4) * 2, 2.5),
				CFrame.new(-14 + index * 3.4, 1.4 + (index % 4), -10.5)
					* CFrame.Angles(0, math.rad(index * 21), math.rad(index * 7)),
				rgb(86 + index * 4, 72, 62)
			)
		end
		newPart("Screen", Vector3.new(11, 7, 0.3), CFrame.new(0, 7.5, -11.2), rgb(236, 230, 212))
		blocks({
			{
				size = Vector3.new(0.4, 6, 0.2),
				at = Vector3.new(-1.2, 7.4, -11),
				color = rgb(60, 56, 52),
			},
			{
				size = Vector3.new(0.4, 6, 0.2),
				at = Vector3.new(1.2, 7.4, -11),
				color = rgb(60, 56, 52),
			},
			{
				size = Vector3.new(2.4, 0.2, 0.2),
				at = Vector3.new(0, 4.4, -11),
				color = rgb(60, 56, 52),
			},
			{
				size = Vector3.new(2, 1.4, 2.2),
				at = Vector3.new(-9, 3.6, 2),
				color = rgb(40, 42, 48),
			},
			{
				size = Vector3.new(3, 3, 0.4),
				at = Vector3.new(-9, 1.5, 2),
				color = rgb(40, 42, 48),
			},
			{
				size = Vector3.new(0.9, 0.9, 0.3),
				at = Vector3.new(-9, 3.6, 1),
				color = rgb(255, 250, 220),
				neon = true,
			},
		})
	else
		-- Pike's garage: concrete, a sodium lamp, a folding table, a car with no one in it.
		blocks({
			{
				size = Vector3.new(2.4, 16, 2.4),
				at = Vector3.new(-9, 8, -9),
				color = rgb(150, 144, 130),
			},
			{
				size = Vector3.new(2.4, 16, 2.4),
				at = Vector3.new(9, 8, -9),
				color = rgb(150, 144, 130),
			},
			{
				size = Vector3.new(9, 2.4, 4),
				at = Vector3.new(-12, 1.4, -5),
				color = rgb(70, 72, 84),
			},
			{
				size = Vector3.new(5, 1.6, 3.6),
				at = Vector3.new(-12, 3.4, -5),
				color = rgb(60, 62, 74),
			},
			{
				size = Vector3.new(5, 0.3, 1.4),
				at = Vector3.new(0, 14.6, -4),
				color = rgb(255, 176, 70),
				neon = true,
			},
		})
		table3(Vector3.new(0, 0, -3.5), 7, rgb(164, 168, 172))
		lampOn(Vector3.new(2.6, 3, -3.2))
		newPart("Papers", Vector3.new(1.8, 0.1, 1.3), CFrame.new(-2, 3.1, -3), rgb(236, 230, 210))
	end
end

local function resetTape()
	drips = {}
	doorLight = nil
	extra = nil
	extraTalk = 0
	shapeStep = 0
	fadeGoal = 0
	fadeNow = 0
end

local function runTape(name: string)
	local look = TAPE_LOOKS[sceneId] or TAPE_LOOKS["tape.orientation"]
	if name == "tape" or name == "start" then
		token += 1
		lighting(look.ambient, look.light)
		if sceneId == "tape.halden" then
			aim(
				Vector3.new(-9, 4.6, 9),
				Vector3.new(-4, 4.5, -5),
				Vector3.new(8, 4.6, 8),
				Vector3.new(4, 4.5, -5),
				14
			)
		else
			aim(
				Vector3.new(0, 4.6, 9),
				Vector3.new(0, 4.5, -5),
				Vector3.new(-0.6, 4.9, 7),
				Vector3.new(0, 4.5, -5),
				40
			)
			camRoll = math.rad(2.5)
		end
	elseif name == "reach" then
		task.spawn(function()
			local began = os.clock()
			local myToken = token
			while token == myToken do
				local alpha = math.clamp((os.clock() - began) / 1.2, 0, 1)
				armAngle = ARM_FORWARD * alpha
				if alpha >= 1 then
					break
				end
				task.wait()
			end
		end)
	elseif name == "static" then
		local myToken = token
		local frame = viewport
		task.spawn(function()
			for _ = 1, 4 do
				if token ~= myToken or frame == nil or frame.Parent == nil then
					return
				end
				frame.Visible = false
				task.wait(0.08)
				frame.Visible = true
				task.wait(0.07)
			end
		end)
	elseif name == "door" then
		if doorLight then
			doorLight.Transparency = 0
		end
		local from = if camera then camera.CFrame.Position else Vector3.new(0, 4, 8)
		aim(from, Vector3.new(0, 4, -5), Vector3.new(-6, 3.4, 1), Vector3.new(-10, 3.6, -11.5), 6)
	elseif name == "fade" then
		fadeGoal = 0.9
	elseif name == "gone" then
		fadeGoal = 1
	elseif name == "dim" then
		lighting(
			look.ambient:Lerp(Color3.new(0, 0, 0), 0.62),
			look.light:Lerp(Color3.new(0, 0, 0), 0.7)
		)
	elseif name == "echo" then
		local pale = newFigure(FIGURE_COLORS.Echo)
		showFigure(pale, true)
		for _, part in pale.parts do
			part.Transparency = 0.45
		end
		extra = pale
		extraRoot = CFrame.lookAt(Vector3.new(7, 0, -1), Vector3.new(0, 0, 9))
	elseif name == "shape" then
		shapeStep += 1
		if extra == nil then
			local dark = newFigure(Color3.fromRGB(8, 8, 10))
			for _, part in dark.parts do
				part.Color = Color3.fromRGB(8, 8, 10)
			end
			extra = dark
		end
		local steps = {
			Vector3.new(-12, 0, -9),
			Vector3.new(-9, 0, -7),
			Vector3.new(-6.5, 0, -5),
			Vector3.new(-4, 0, -4),
		}
		local spot = steps[math.min(shapeStep, #steps)]
		extraRoot = CFrame.lookAt(spot, Vector3.new(0, 0, -5.6))
	end
end

--------------------------------------------------------------------------------------------
-- Opening and closing

local function step()
	local view = camera
	if view == nil then
		return
	end
	local alpha = math.clamp((os.clock() - camStart) / camSeconds, 0, 1)
	local eased = alpha * alpha * (3 - 2 * alpha)
	view.CFrame = camFrom:Lerp(camTo, eased) * CFrame.Angles(0, 0, camRoll)
	local who = figure
	if who then
		local speaking = os.clock() < talkUntil
		local bob = if speaking then math.sin(os.clock() * 15) * 0.07 else 0
		if setName == "tape" then
			figureRoot = CFrame.lookAt(Vector3.new(0, 0, -5.6), Vector3.new(0, 0, 9))
		end
		pose(who, figureRoot, armAngle, 0, bob)
		if fadeNow ~= fadeGoal then
			fadeNow = math.min(fadeGoal, fadeNow + 0.004)
			for _, part in who.parts do
				part.Transparency = fadeNow
			end
		end
	end
	local other = extra
	if other then
		local speaking = os.clock() < extraTalk
		pose(other, extraRoot, 0, 0, if speaking then math.sin(os.clock() * 15) * 0.07 else 0)
	end
	for index, drop in drips do
		local y = 9 - ((os.clock() * 4 + index * 1.7) % 9)
		drop.CFrame = CFrame.new(drop.Position.X, y, drop.Position.Z)
	end
end

-- Builds the set into `container` (a Frame) and starts the camera. `set` is "office" or "tape".
function Stage.open(container: GuiObject, set: string, id: string?)
	Stage.close()
	setName = set
	sceneId = id or ""
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Stage"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(16, 17, 20)
	frame.BorderSizePixel = 0
	frame.Parent = container
	viewport = frame
	local view = Instance.new("Camera")
	view.FieldOfView = if set == "tape" then 46 else 58
	view.Parent = frame
	frame.CurrentCamera = view
	camera = view
	camRoll = 0
	ceilingLights = {}
	melt = { panel = nil, glow = nil, drips = {}, progress = 0 }
	if set == "tape" then
		resetTape()
		buildTape(sceneId)
		figureRoot = CFrame.lookAt(Vector3.new(0, 0, -5.6), Vector3.new(0, 0, 9))
		figure = newFigure(DEFAULT_FIGURE)
		runTape("tape")
	else
		buildOffice()
		figure = newFigure(FIGURE_COLORS.Theo)
	end
	camFrom = view.CFrame
	camTo = view.CFrame
	stepConnection = RunService.RenderStepped:Connect(step)
end

-- A `stage` beat. Unknown names do nothing.
function Stage.run(name: string)
	if viewport == nil then
		return
	end
	local ok, problem = pcall(function()
		if setName == "tape" then
			runTape(name)
		else
			runOffice(name)
		end
	end)
	if not ok then
		warn("Stage:", problem)
	end
end

-- A line is starting: the figure on screen talks for about as long as the line takes to type.
function Stage.speak(speaker: string, seconds: number)
	local who = figure
	if who == nil then
		return
	end
	if setName == "tape" and speaker == "Echo" and extra ~= nil then
		extraTalk = os.clock() + seconds
	elseif setName == "tape" and speaker ~= "Theo" then
		recolor(who, FIGURE_COLORS[speaker] or DEFAULT_FIGURE)
		talkUntil = os.clock() + seconds
	elseif setName == "office" and speaker == "Theo" then
		talkUntil = os.clock() + seconds
	end
end

function Stage.close()
	token += 1
	dotsToken += 1
	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
	if viewport then
		viewport:Destroy()
	end
	viewport = nil
	camera = nil
	figure = nil
	ceilingLights = {}
	melt = { panel = nil, glow = nil, drips = {}, progress = 0 }
	resetTape()
	talkUntil = 0
end

return Stage
