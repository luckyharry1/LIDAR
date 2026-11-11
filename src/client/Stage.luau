--!strict
-- The picture for a staged scene (a LoreText scene with a `stage`): a small set cut from blocks,
-- lit by a ViewportFrame's own ambient light so the dark world is never touched, a camera, and
-- blocky figures with faces. Cutscene.luau opens a stage, calls Stage.run(cue) at each `stage`
-- beat (it returns the seconds the scene should wait), and Stage.speak when a line starts.
--
-- Everything that can be checked with plain maths lives in src/shared/pure/StageData.luau (the
-- blocks of every set, every camera move) and is tested by tests/StageTests.luau. This file
-- only turns that data into Parts and animates what moves.
--
-- Sets (a scene's `stage`): "office" (the opening), "tape" (one room per tape id) and "lamp"
-- (the finale and the endings). Any other name shows no picture at all.
--
-- A ViewportFrame knows no PointLights, shadows, bloom or particles, and Neon is a flat bright
-- colour: so a light is a bright Neon part, and a dark room is a dark Ambient with a few bright
-- parts. Every function is safe to call at any time; a mistake here must never stop a cutscene.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(script.Parent.Audio)
local Dots = require(script.Parent.Dots)
local StageData = require(ReplicatedStorage.Shared.pure.StageData)

local Stage = {}

type Vec = StageData.Vec
type Room = StageData.Room
type Cue = StageData.Cue
type Seg = StageData.Seg

type Face = { part: Part, to: string, offset: CFrame, alpha: number }
type Figure = {
	name: string,
	parts: { [string]: Part },
	faces: { Face },
	ghost: number, -- a permanent see-through-ness (the Echo)
	coat: Color3,
}
type Track = { at: number, segs: { Seg } }

local SKIN = Color3.fromRGB(222, 184, 150)
local LEG_COLOR = Color3.fromRGB(46, 48, 58)
local EYE_COLOR = Color3.fromRGB(22, 22, 26)
local DEFAULT_COAT = Color3.fromRGB(110, 110, 110)
local ARM_FORWARD = math.pi / 2 -- a hanging arm swung to point the way the figure faces
local DOT_POP_SECONDS = 0.35
local DOT_POP_SIZE = 1.9
local TICK_GAP = 0.07

-- The opening
local THEO_START = Vector3.new(3, 0, -4)
local THEO_WALL = Vector3.new(-2, 0, -23.4)
local WALK_SECONDS = 3.4
local MELT_BEGIN = 3.6
local MELT_SECONDS = 2.2
local PULL_SECONDS = 1
local HOLE_X = -0.75
local WALL_FACE = -25.5
local STUTTER_AT = { 1.0, 1.12, 1.3, 1.38, 1.55, 1.62, 1.78 } -- seconds after the pull begins
local STUTTER_ON = { false, true, false, true, false, true, false }
local DARK_SECONDS = 2.5

-- The lamp room
local DESK_SPOT = Vector3.new(0, 0, -7.4)
local THEO_SPOT = Vector3.new(2.4, 0, -3.4)
local BAR_Z = -9.6
local BOARD_FRONT = Vector3.new(-15.5, 6.2, -20.6)

-- The tape cues
local SPEAKER_SPOT = Vector3.new(0, 0, -5.6)
local ECHO_SPOT = Vector3.new(2.4, 0, -8.8)
local SHAPE_SIZES = { 1.2, 2, 3.2, 5 }

local viewport: ViewportFrame? = nil
local camera: Camera? = nil
local stepConnection: RBXScriptConnection? = nil
local room: Room? = nil

local named: { [string]: Part } = {}
local figures: { main: Figure?, second: Figure?, extra: Figure? } = {}
local track: { Track } = {}
local openedAt = 0
local timers: { [string]: number } = {}
local talkUntil: { main: number, second: number, extra: number } =
	{ main = 0, second = 0, extra = 0 }
local lightsOn = true
local fadeGoal = 0 -- how far the speaker has faded from the picture, 0 to 1
local fadeNow = 0
local shapeStep = 0
local shapeSize = 0
local veil = { r = 1, g = 1, b = 1, alpha = 0 }
local dead = false
local drips: { Part } = {}

local dotList: { StageData.Dot } = {}
local dotStart = 0
local dotSeconds = 1
local dotNext = 1
local dotSize = 0.4
local recent: { { part: Part, born: number, size: number } } = {}
local lastTick = 0
local boardFilled: { StageData.BoardDot } = {}
local boardGap: { StageData.BoardDot } = {}
local boardNext = 1
local gapNext = 1

local function v3(vec: Vec): Vector3
	return Vector3.new(vec[1], vec[2], vec[3])
end

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3])
end

local function smooth(u: number): number
	local x = math.clamp(u, 0, 1)
	return x * x * (3 - 2 * x)
end

local function part(name: string): Part?
	return named[name]
end

--------------------------------------------------------------------------------------------
-- Parts

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	neon: boolean?,
	shape: Enum.PartType?
): Part
	local made = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = false
	made.CanTouch = false
	made.CanQuery = false
	made.CastShadow = false
	made.Size = size
	made.CFrame = cframe
	made.Color = color
	made.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	made.Shape = shape or Enum.PartType.Block
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	made.Parent = parent
	return made
end

local function partFromBlock(parent: Instance, block: StageData.Block): Part
	local shape = Enum.PartType.Block
	if block.shape == "ball" then
		shape = Enum.PartType.Ball
	elseif block.shape == "cylinder" then
		shape = Enum.PartType.Cylinder
	end
	local size = v3(block.size)
	local cframe = CFrame.new(v3(block.at))
	local rod = block.rod
	if rod then
		local from, to = v3(rod[1]), v3(rod[2])
		size = Vector3.new(block.size[1], block.size[2], (to - from).Magnitude)
		cframe = CFrame.lookAt((from + to) / 2, to)
	elseif block.rot then
		local rot = block.rot
		cframe = cframe * CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
	end
	local made = newPart(parent, block.name, size, cframe, rgb(block.color), block.neon, shape)
	if block.hidden then
		made.Transparency = 1
	elseif block.alpha then
		made.Transparency = block.alpha
	end
	return made
end

--------------------------------------------------------------------------------------------
-- Figures: a head with a face, a body, and a few small parts that tell one person from another

local function newFigure(parent: Instance, name: string): Figure
	local parts: { [string]: Part } = {}
	local origin = CFrame.new()
	parts.Head =
		newPart(parent, "Head", Vector3.new(1.2, 1.2, 1.2), origin, SKIN, false, Enum.PartType.Ball)
	parts.Torso = newPart(parent, "Torso", Vector3.new(1.8, 2, 0.9), origin, DEFAULT_COAT)
	parts.ArmL = newPart(parent, "ArmL", Vector3.new(0.7, 1.9, 0.7), origin, DEFAULT_COAT)
	parts.ArmR = newPart(parent, "ArmR", Vector3.new(0.7, 1.9, 0.7), origin, DEFAULT_COAT)
	parts.LegL = newPart(parent, "LegL", Vector3.new(0.8, 2, 0.8), origin, LEG_COLOR)
	parts.LegR = newPart(parent, "LegR", Vector3.new(0.8, 2, 0.8), origin, LEG_COLOR)
	parts.EyeL = newPart(parent, "EyeL", Vector3.new(0.17, 0.22, 0.1), origin, EYE_COLOR)
	parts.EyeR = newPart(parent, "EyeR", Vector3.new(0.17, 0.22, 0.1), origin, EYE_COLOR)
	parts.Mouth = newPart(parent, "Mouth", Vector3.new(0.4, 0.05, 0.1), origin, EYE_COLOR)
	local who: Figure = { name = "", parts = parts, faces = {}, ghost = 0, coat = DEFAULT_COAT }
	return who
end

local function removeFaces(who: Figure)
	for _, face in who.faces do
		face.part:Destroy()
	end
	who.faces = {}
end

-- Gives a figure a person's coat and the small parts that make them them.
local function dress(who: Figure, name: string)
	who.name = name
	removeFaces(who)
	local triple = StageData.coats[name]
	who.coat = if triple then rgb(triple) else DEFAULT_COAT
	for _, key in { "Torso", "ArmL", "ArmR" } do
		who.parts[key].Color = who.coat
	end
	local parent = who.parts.Head.Parent
	for _, item in StageData.features[name] or {} do
		local shape = Enum.PartType.Block
		if item.shape == "ball" then
			shape = Enum.PartType.Ball
		end
		local made = newPart(
			parent :: Instance,
			"Feature",
			v3(item.size),
			CFrame.new(),
			rgb(item.color),
			false,
			shape
		)
		table.insert(who.faces, {
			part = made,
			to = item.to,
			offset = CFrame.new(v3(item.at)),
			alpha = item.alpha or 0,
		})
	end
end

-- 0 is solid, 1 is gone; `ghost` figures never get more solid than they are.
local function setSeeThrough(who: Figure, amount: number)
	for _, body in who.parts do
		body.Transparency = math.clamp(who.ghost + amount, 0, 1)
	end
	for _, face in who.faces do
		face.part.Transparency = math.clamp(face.alpha + who.ghost + amount, 0, 1)
	end
end

-- Sets every part of a figure from a root (the feet, facing along the root's look vector).
local function pose(
	who: Figure,
	root: CFrame,
	right: number,
	left: number,
	bob: number,
	mouth: number,
	stride: number
)
	local parts = who.parts
	local torso = root * CFrame.new(0, 3, 0)
	local head = root * CFrame.new(0, 4.5 + bob, 0)
	parts.Torso.CFrame = torso
	parts.Head.CFrame = head
	parts.LegL.CFrame = root
		* CFrame.new(-0.45, 2, 0)
		* CFrame.Angles(stride, 0, 0)
		* CFrame.new(0, -1, 0)
	parts.LegR.CFrame = root
		* CFrame.new(0.45, 2, 0)
		* CFrame.Angles(-stride, 0, 0)
		* CFrame.new(0, -1, 0)
	parts.ArmR.CFrame = root
		* CFrame.new(1.25, 3.95, 0)
		* CFrame.Angles(right, 0, 0)
		* CFrame.new(0, -0.95, 0)
	parts.ArmL.CFrame = root
		* CFrame.new(-1.25, 3.95, 0)
		* CFrame.Angles(left, 0, 0)
		* CFrame.new(0, -0.95, 0)
	parts.EyeL.CFrame = head * CFrame.new(-0.24, 0.1, -0.56)
	parts.EyeR.CFrame = head * CFrame.new(0.24, 0.1, -0.56)
	parts.Mouth.Size = Vector3.new(0.4, 0.05 + 0.2 * mouth, 0.1)
	parts.Mouth.CFrame = head * CFrame.new(0, -0.27, -0.57)
	for _, face in who.faces do
		face.part.CFrame = (if face.to == "head" then head else torso) * face.offset
	end
end

-- How open a speaker's mouth is, and how far the head bobs, at this moment.
local function talk(until_: number, now: number): (number, number)
	if now >= until_ then
		return 0, 0
	end
	local wave = math.sin(now * 14)
	return math.clamp(0.35 + wave * 0.6, 0, 1), math.sin(now * 15) * 0.06
end

--------------------------------------------------------------------------------------------
-- The camera, the lights and the veil

local function setLighting(ambient: Color3, light: Color3)
	local frame = viewport
	if frame then
		frame.Ambient = ambient
		frame.LightColor = light
	end
end

local function setCamera(segs: { Seg }, startAt: number?, keep: boolean?)
	local when = startAt or os.clock()
	if keep then
		table.insert(track, { at = when, segs = segs })
	else
		track = { { at = when, segs = segs } }
	end
	local view = camera
	if view and when <= os.clock() then
		local position, lookAt = StageData.cameraAt(segs, os.clock() - when)
		view.CFrame = CFrame.lookAt(v3(position), v3(lookAt))
	end
end

local function cueOf(name: string): Cue?
	local def = room
	if def then
		return def.cues[name]
	end
	return nil
end

local function setVeil(color: Color3?, alpha: number)
	if color then
		veil.r, veil.g, veil.b = color.R, color.G, color.B
	end
	veil.alpha = alpha
end

--------------------------------------------------------------------------------------------
-- Dots: the scanner draws a room out of the dark

local function dotColor(kind: string): Color3
	return Dots.color(kind :: any)
end

local function tick(now: number)
	if now - lastTick >= TICK_GAP then
		lastTick = now
		Audio.blip(1.3 + math.random() * 0.9, 0.09)
	end
end

local function addDot(
	parent: Instance,
	x: number,
	y: number,
	z: number,
	color: Color3,
	size: number
)
	local made = newPart(
		parent,
		"Dot",
		Vector3.new(size, size, size),
		CFrame.new(x, y, z),
		color,
		true,
		Enum.PartType.Ball
	)
	made.Size = Vector3.new(size, size, size) * DOT_POP_SIZE
	table.insert(recent, { part = made, born = os.clock(), size = size })
end

local function clearDots()
	local frame = viewport
	if frame then
		for _, child in frame:GetChildren() do
			if child.Name == "Dot" then
				child:Destroy()
			end
		end
	end
	dotList = {}
	dotNext = 1
	recent = {}
	boardFilled, boardGap = {}, {}
	boardNext, gapNext = 1, 1
end

-- Starts the room's scan `delay` seconds from now.
local function startScan(delay: number)
	local def = room
	if def == nil or def.scan == nil then
		return
	end
	clearDots()
	dotList = StageData.scanDots(def.blocks, def.scan)
	dotStart = os.clock() + delay
	dotSeconds = def.scan.seconds
	dotSize = def.scan.size
	dotNext = 1
end

local function updateDots(now: number)
	local frame = viewport
	if frame == nil then
		return
	end
	if dotNext <= #dotList then
		local progress = (now - dotStart) / dotSeconds
		local added = 0
		while dotNext <= #dotList and dotList[dotNext].t <= progress do
			local dot = dotList[dotNext]
			addDot(frame, dot.x, dot.y, dot.z, dotColor(dot.kind), dotSize)
			dotNext += 1
			added += 1
		end
		if added > 0 then
			tick(now)
		end
	end
	-- the chalkboard
	local boardAt = timers.board
	if boardAt then
		local elapsed = now - boardAt
		local added = 0
		while boardNext <= #boardFilled and boardFilled[boardNext].t * 3 <= elapsed do
			local dot = boardFilled[boardNext]
			addDot(
				frame,
				BOARD_FRONT.X + dot.x,
				BOARD_FRONT.Y + dot.y,
				BOARD_FRONT.Z,
				dotColor("wall"),
				0.34
			)
			boardNext += 1
			added += 1
		end
		while gapNext <= #boardGap and 3.4 + boardGap[gapNext].t * 1.4 <= elapsed do
			local dot = boardGap[gapNext]
			addDot(
				frame,
				BOARD_FRONT.X + dot.x,
				BOARD_FRONT.Y + dot.y,
				BOARD_FRONT.Z,
				dotColor("objective"),
				0.4
			)
			gapNext += 1
			added += 1
		end
		if added > 0 then
			tick(now)
		end
	end
	-- a new dot starts big and settles
	local index = 1
	while index <= #recent do
		local entry = recent[index]
		local age = (now - entry.born) / DOT_POP_SECONDS
		local size = entry.size
		if age >= 1 or entry.part.Parent == nil then
			entry.part.Size = Vector3.new(size, size, size)
			table.remove(recent, index)
		else
			size *= DOT_POP_SIZE - (DOT_POP_SIZE - 1) * smooth(age)
			entry.part.Size = Vector3.new(size, size, size)
			index += 1
		end
	end
end

--------------------------------------------------------------------------------------------
-- Building a room

local function resetState()
	timers = {}
	figures = {}
	track = {}
	talkUntil = { main = 0, second = 0, extra = 0 }
	lightsOn = true
	fadeGoal, fadeNow = 0, 0
	shapeStep, shapeSize = 0, 0
	veil.alpha = 0
	dead = false
	dotList, recent = {}, {}
	dotNext = 1
	boardFilled, boardGap = {}, {}
	boardNext, gapNext = 1, 1
	drips = {}
end

local function buildRoom(def: Room)
	local frame = viewport
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if child ~= camera then
			child:Destroy()
		end
	end
	resetState()
	named = {}
	room = def
	for _, block in def.blocks do
		local made = partFromBlock(frame, block)
		if named[block.name] == nil then
			named[block.name] = made
		end
		if block.name == "Drip" then
			table.insert(drips, made)
		end
	end
	setLighting(rgb(def.ambient), rgb(def.light))
	frame.BackgroundColor3 = if def.id == "wake"
		then Color3.fromRGB(3, 3, 4)
		else Color3.fromRGB(16, 17, 20)
	if def.id == "lamp" then
		frame.LightDirection = Vector3.new(0.2, -0.5, -1)
	else
		frame.LightDirection = Vector3.new(-0.3, -1, -0.4)
	end
	local opening = def.cues[def.start]
	if opening and opening.segs then
		setCamera(opening.segs)
	end
	-- the people in it
	if def.id == "office" then
		local theo = newFigure(frame, "Theo")
		dress(theo, "Theo")
		figures.main = theo
	elseif def.id == "morning" then
		local theo = newFigure(frame, "Theo")
		dress(theo, "Theo")
		figures.main = theo
	elseif def.id == "lamp" then
		local ines = newFigure(frame, "Ines")
		dress(ines, "Ines")
		figures.main = ines
		local theo = newFigure(frame, "Theo")
		dress(theo, "Theo")
		figures.second = theo
	end
end

--------------------------------------------------------------------------------------------
-- Moving things, room by room

local function setLights(on: boolean)
	if on == lightsOn then
		return
	end
	lightsOn = on
	local def = room
	if def == nil then
		return
	end
	for index = 1, 4 do
		local lamp = part("CeilingLight" .. index)
		if lamp then
			lamp.Transparency = if on then 0 else 1
		end
	end
	if on then
		setLighting(rgb(def.ambient), rgb(def.light))
	else
		setLighting(Color3.fromRGB(8, 8, 10), Color3.fromRGB(10, 10, 12))
	end
end

-- The wall gives: a bright hole opens in it, the paper runs, light spills on the floor.
local function setMelt(progress: number)
	local e = progress
	local on = progress > 0.02
	local width = 0.35 + 3.05 * e
	local height = 0.35 + 6.65 * e
	local centre = 4 - 0.5 * e
	local hole = part("MeltHole")
	if hole then
		hole.Transparency = if on then 0 else 1
		hole.Size = Vector3.new(width, height, 0.06)
		hole.CFrame = CFrame.new(HOLE_X, centre, WALL_FACE + 0.1)
	end
	local rim = part("MeltRim")
	if rim then
		rim.Transparency = if on then 0 else 1
		rim.Size = Vector3.new(width + 0.9, height + 0.9, 0.06)
		rim.CFrame = CFrame.new(HOLE_X, centre, WALL_FACE + 0.04)
	end
	local stain = part("MeltStain")
	if stain then
		stain.Transparency = 1 - 0.85 * e
	end
	local pool = part("MeltFloor")
	if pool then
		pool.Transparency = if on then 0.5 - 0.3 * e else 1
		pool.Size = Vector3.new(2 + 4.5 * e, 0.05, 2 + 3 * e)
		pool.CFrame = CFrame.new(HOLE_X, 0.04, WALL_FACE + 1.5 + 1.5 * e)
	end
	local top = centre + height / 2 + 0.3
	for index = 1, 6 do
		local drip = part("MeltDrip" .. index)
		if drip then
			local reach = e * (2.6 + 0.8 * (index % 3))
			local start = math.min(top - (index % 2) * 0.8, 9)
			reach = math.min(reach, start)
			drip.Transparency = if progress <= 0.04 then 1 else 0
			local x = drip.Position.X
			drip.Size = Vector3.new(drip.Size.X, math.max(reach, 0.1), 0.1)
			drip.CFrame = CFrame.new(x, start - reach / 2, WALL_FACE + 0.12)
		end
	end
end

local function animateOffice(now: number)
	local who = figures.main
	if who == nil then
		return
	end
	local leanAt = timers.lean
	local darkAt = timers.dark
	local t = if leanAt then now - leanAt else -1
	local root: CFrame
	local right, left, stride = 0, 0, 0
	if t < 0 then
		root = CFrame.lookAt(THEO_START, Vector3.new(6, 0, -6))
	else
		local walk = math.clamp(t / WALK_SECONDS, 0, 1)
		local melt = math.clamp((t - MELT_BEGIN) / MELT_SECONDS, 0, 1)
		local position = THEO_START:Lerp(THEO_WALL, walk) + Vector3.new(0, 0, -0.8 * melt)
		local heading = (THEO_WALL - THEO_START).Unit:Lerp(Vector3.new(0, 0, -1), walk)
		if darkAt then
			local pull = math.clamp((now - darkAt) / PULL_SECONDS, 0, 1)
			position += Vector3.new(0, 0, -2.4 * pull * pull)
		end
		root = CFrame.lookAt(position, position + heading)
		if walk < 1 then
			stride = math.sin(t * 9) * 0.55
		end
		local raise = smooth((t - 2.9) / 0.5)
		right = -math.sin(t * 9) * 0.5 * (1 - raise) * (if walk < 1 then 1 else 0)
			+ ARM_FORWARD * raise
		left = if walk < 1 then math.sin(t * 9) * 0.5 else 0
		setMelt(melt)
		if darkAt then
			local d = now - darkAt
			local on = true
			for index, at in STUTTER_AT do
				if d >= at then
					on = STUTTER_ON[index]
				end
			end
			setLights(on)
			if d >= DARK_SECONDS and not dead then
				dead = true
				if viewport then
					viewport.Visible = false
				end
			end
		end
	end
	local mouth, bob = talk(talkUntil.main, now)
	pose(who, root, right, left, bob, mouth, stride)
end

local function animateMorning(now: number)
	local who = figures.main
	if who then
		local root = CFrame.lookAt(Vector3.new(0, 0, -22.2), Vector3.new(0, 0, 9))
		local mouth, bob = talk(talkUntil.main, now)
		pose(who, root, 0, 0, bob, mouth, 0)
	end
	local lens = part("ScannerLens")
	local scanAt = timers.scan42
	if lens and scanAt then
		local on = now - scanAt >= 0
		lens.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		lens.Color = if on then Color3.fromRGB(235, 240, 255) else Color3.fromRGB(50, 54, 62)
	end
	local sweep = timers.morning
	if sweep then
		setVeil(Color3.new(1, 1, 1), 1 - smooth((now - sweep) / 1.4))
	end
end

local function animateWake(now: number)
	local smear = part("Smear")
	if smear then
		smear.Transparency = 0.55 + 0.45 * smooth((now - (timers.wake or now)) / 2.4)
	end
end

local function animateLamp(now: number)
	local ines, theo = figures.main, figures.second
	if ines == nil or theo == nil then
		return
	end
	local inesRoot = CFrame.lookAt(DESK_SPOT, DESK_SPOT + Vector3.new(0, 0, 1))
	local theoRoot = CFrame.lookAt(THEO_SPOT, DESK_SPOT)
	local inesArm, theoArm, theoStride = 0, 0, 0
	local climbAt = timers.climb
	local takeAt = timers.take
	local theoLeft = 0
	if takeAt then
		local t = now - takeAt
		local walkIn = smooth(t / 1.6)
		local theoPos = THEO_SPOT:Lerp(Vector3.new(2.6, 0, BAR_Z + 1.25), walkIn)
		theoRoot = CFrame.lookAt(theoPos, Vector3.new(0, 0, theoPos.Z))
		theoArm = ARM_FORWARD * smooth((t - 1.1) / 0.5)
		if t < 1.6 then
			theoStride = math.sin(t * 9) * 0.5
		end
		local inesPos = DESK_SPOT:Lerp(Vector3.new(-2.6, 0, BAR_Z - 1.25), smooth(t / 1.4))
		-- she lets go, then steps back
		local letGo = smooth((t - 2.3) / 0.5)
		inesPos = inesPos:Lerp(Vector3.new(-3.8, 0, BAR_Z - 1.25), smooth((t - 2.6) / 0.8))
		inesRoot = CFrame.lookAt(inesPos, inesPos + Vector3.new(1, 0, 0))
		inesArm = ARM_FORWARD * smooth((t - 0.9) / 0.5) * (1 - letGo)
		-- the Lamp flares
		local flare = smooth((t - 3) / 0.6)
		local halo = part("LampHalo")
		if halo then
			local size = 8.5 + 6.5 * flare
			halo.Size = Vector3.new(size, size, size)
			halo.Transparency = 0.86 - 0.3 * flare
		end
		local bulb = part("LampBulb")
		if bulb then
			bulb.Size = Vector3.new(4.8, 4.8, 4.8) * (1 + 0.15 * flare)
		end
		local pool = part("LampPool")
		if pool then
			pool.Size = Vector3.new(14 + 10 * flare, 0.05, 14 + 10 * flare)
		end
		local pulse = math.clamp(1 - (t - 3) / 0.9, 0, 1) * smooth((t - 2.9) / 0.1)
		setVeil(Color3.new(1, 1, 1), 0.55 * pulse)
	end
	if climbAt then
		local t = now - climbAt
		local u = math.clamp(t / 5.2, 0, 1)
		local height = 1 + 27 * u
		local root = CFrame.lookAt(Vector3.new(14, height, -13.55), Vector3.new(14, height, -20))
		theoRoot = root
		local swing = math.sin(t * 6)
		theoArm = math.pi * 0.8 + swing * 0.3
		theoLeft = math.pi * 0.8 - swing * 0.3
		theoStride = swing * 0.5
		setVeil(Color3.new(1, 1, 1), smooth((t - 4.1) / 1.1))
	end
	local mouthI, bobI = talk(talkUntil.main, now)
	local mouthT, bobT = talk(talkUntil.second, now)
	pose(ines, inesRoot, inesArm, 0, bobI, mouthI, 0)
	pose(theo, theoRoot, theoArm, theoLeft, bobT, mouthT, theoStride)
	-- the ladder: a line of light runs up, the door at the top is edged in daylight
	local ladderAt = timers.ladder
	local keepAt = timers.keep
	if ladderAt then
		local u = smooth((now - ladderAt) / 2.4)
		local light = part("LadderLight")
		if light then
			local height = 0.5 + 31.5 * u
			light.Transparency = 0
			light.Size = Vector3.new(0.25, height, 0.25)
			light.CFrame = CFrame.new(14, 0.1 + height / 2, -14.5)
		end
		local edge = if u > 0.92 then 0 else 1
		local fadeOut = 0
		if keepAt then
			fadeOut = smooth((now - keepAt) / 1.8)
		end
		for _, name in { "DoorL", "DoorR", "DoorHead" } do
			local piece = part(name)
			if piece then
				piece.Transparency = if edge == 1 then 1 else fadeOut
			end
		end
		if keepAt and light then
			light.Transparency = fadeOut
		end
	end
	if keepAt then
		for index = 1, 6 do
			local small = part("Relay" .. index)
			if small then
				small.Transparency = if now - keepAt >= 1.6 + index * 0.55 then 0 else 1
			end
		end
	end
end

local function animateTape(now: number)
	local who = figures.main
	local look = room
	if look == nil then
		return
	end
	if who then
		local root = CFrame.lookAt(SPEAKER_SPOT, SPEAKER_SPOT + Vector3.new(0, 0, 1))
		local mouth, bob = talk(talkUntil.main, now)
		local reachAt = timers.reach
		local view = camera
		local arm = part("ReachArm")
		local hand = part("ReachHand")
		if reachAt and view then
			local t = now - reachAt
			local e = smooth(t / 1.1)
			local shoulder = (root * CFrame.new(-1.25, 3.95, 0)).Position
			local target = view.CFrame.Position + view.CFrame.LookVector * 1.1
			local tip = shoulder:Lerp(target, e)
			if arm and hand then
				arm.Transparency = 0
				hand.Transparency = 0
				local distance = math.max((tip - shoulder).Magnitude, 0.1)
				local size = 0.7 + 0.5 * e
				arm.Size = Vector3.new(size, size, distance)
				arm.CFrame = CFrame.lookAt((shoulder + tip) / 2, tip)
				hand.Size = Vector3.new(size * 1.3, size * 1.3, size * 1.3)
				hand.CFrame = CFrame.new(tip)
			end
			who.parts.ArmL.Transparency = 1
		end
		pose(who, root, 0, 0, bob, mouth, 0)
		if reachAt then
			who.parts.ArmL.Transparency = 1
		end
		if fadeNow ~= fadeGoal then
			local speed = if fadeGoal >= 1 then 0.5 else 0.3
			local delta = speed / 60
			fadeNow = if fadeNow < fadeGoal
				then math.min(fadeGoal, fadeNow + delta)
				else math.max(fadeGoal, fadeNow - delta)
			setSeeThrough(who, fadeNow)
		end
	end
	local other = figures.extra
	if other then
		local root = CFrame.lookAt(ECHO_SPOT, ECHO_SPOT + Vector3.new(0, 0, 1))
		local mouth, bob = talk(talkUntil.extra, now)
		pose(other, root, 0, 0, bob, mouth, 0)
	end
	local dimAt = timers.dim
	if dimAt then
		local e = smooth((now - dimAt) / 1.6)
		setLighting(
			rgb(look.ambient):Lerp(Color3.new(0, 0, 0), 0.62 * e),
			rgb(look.light):Lerp(Color3.new(0, 0, 0), 0.7 * e)
		)
	end
	-- the shape in the slide, nearer each time
	if shapeStep > 0 then
		local goal = SHAPE_SIZES[math.min(shapeStep, #SHAPE_SIZES)]
		shapeSize += (goal - shapeSize) * 0.08
		local body = part("ShapeBody")
		local head = part("ShapeHead")
		local armL = part("ShapeArmL")
		local armR = part("ShapeArmR")
		if body and head and armL and armR then
			local x, z, base = 2.4, -10.9, 3
			local s = shapeSize
			body.Size = Vector3.new(s * 0.3, s * 0.55, 0.15)
			body.CFrame = CFrame.new(x, base + s * 0.275, z)
			head.Size = Vector3.new(s * 0.22, s * 0.22, s * 0.22)
			head.CFrame = CFrame.new(x, base + s * 0.55 + s * 0.11, z)
			armL.Size = Vector3.new(s * 0.08, s * 0.5, 0.12)
			armL.CFrame = CFrame.new(x - s * 0.2, base + s * 0.3, z)
			armR.Size = Vector3.new(s * 0.08, s * 0.5, 0.12)
			armR.CFrame = CFrame.new(x + s * 0.2, base + s * 0.3, z)
		end
	end
	for index, drop in drips do
		local y = 9 - ((now * 4 + index * 1.7) % 9)
		drop.CFrame = CFrame.new(drop.Position.X, y, drop.Position.Z)
	end
	local deadAt = timers.dead
	if deadAt and now >= deadAt and not dead then
		dead = true
		if viewport then
			viewport.Visible = false
		end
	end
end

local function updateVeil()
	local view = camera
	local frame = viewport
	if view == nil or frame == nil then
		return
	end
	local cover = frame:FindFirstChild("Veil") :: Part?
	if veil.alpha <= 0.01 then
		if cover then
			cover.Transparency = 1
		end
		return
	end
	if cover == nil then
		cover =
			newPart(frame, "Veil", Vector3.new(6, 4, 0.02), CFrame.new(), Color3.new(1, 1, 1), true)
	end
	local made = cover :: Part
	made.Color = Color3.new(veil.r, veil.g, veil.b)
	made.Transparency = 1 - math.clamp(veil.alpha, 0, 1)
	made.CFrame = view.CFrame * CFrame.new(0, 0, -1)
end

--------------------------------------------------------------------------------------------
-- Every frame

local function step()
	local view = camera
	local frame = viewport
	local def = room
	if view == nil or frame == nil or def == nil then
		return
	end
	local now = os.clock()
	local active = track[1]
	for _, item in track do
		if item.at <= now then
			active = item
		end
	end
	if active then
		local position, lookAt, roll = StageData.cameraAt(active.segs, now - active.at)
		view.CFrame = CFrame.lookAt(v3(position), v3(lookAt)) * CFrame.Angles(0, 0, math.rad(roll))
	end
	local id = def.id
	if id == "office" then
		animateOffice(now)
	elseif id == "morning" then
		animateMorning(now)
	elseif id == "wake" then
		animateWake(now)
	elseif id == "lamp" then
		animateLamp(now)
	else
		animateTape(now)
	end
	updateDots(now)
	updateVeil()
end

--------------------------------------------------------------------------------------------
-- Cues

local cues: { [string]: () -> number } = {}

local function holdOf(name: string): number
	local cue = cueOf(name)
	return if cue and cue.hold then cue.hold else 0
end

local function playCamera(name: string)
	local cue = cueOf(name)
	if cue and cue.segs then
		setCamera(cue.segs)
	end
end

local function inRoom(...: string): boolean
	local def = room
	if def == nil then
		return false
	end
	for _, id in { ... } do
		if def.id == id then
			return true
		end
	end
	return false
end

cues.office = function(): number
	if not inRoom("office") then
		return 0
	end
	-- the opening shot is already rolling; only restart it if the scene has been going a while
	if os.clock() - openedAt > 2 then
		playCamera("office")
	end
	timers.office = os.clock()
	startScan(0.4)
	return holdOf("office")
end

cues.lean = function(): number
	if not inRoom("office") then
		return 0
	end
	clearDots()
	timers.lean = os.clock()
	timers.dark = nil
	playCamera("lean")
	return holdOf("lean")
end

cues.dark = function(): number
	if not inRoom("office") then
		return 0
	end
	local now = os.clock()
	if timers.lean == nil then
		timers.lean = now - 6
	end
	local startsAt = math.max(now, (timers.lean :: number) + 5.8)
	timers.dark = startsAt
	local cue = cueOf("dark")
	if cue and cue.segs then
		setCamera(cue.segs, startsAt, true)
	end
	return startsAt + DARK_SECONDS - now
end

cues.wake = function(): number
	local def = StageData.rooms.wake
	if viewport == nil or def == nil or not inRoom("office", "wake") then
		return 0
	end
	buildRoom(def)
	viewport.Visible = true
	timers.wake = os.clock()
	startScan(0.9)
	return holdOf("wake")
end

cues.lamp = function(): number
	if not inRoom("lamp") then
		return 0
	end
	local now = os.clock()
	if now - openedAt > 2 then
		playCamera("lamp")
	end
	return holdOf("lamp")
end

cues.board = function(): number
	if not inRoom("lamp") then
		return 0
	end
	boardFilled, boardGap = StageData.boardDots(300, 70, 5)
	boardNext, gapNext = 1, 1
	timers.board = os.clock()
	playCamera("board")
	return holdOf("board")
end

cues.ladder = function(): number
	if not inRoom("lamp") then
		return 0
	end
	timers.ladder = os.clock()
	playCamera("ladder")
	return holdOf("ladder")
end

cues.climb = function(): number
	if not inRoom("lamp") then
		return 0
	end
	timers.climb = os.clock()
	timers.ladder = timers.ladder or (os.clock() - 3)
	playCamera("climb")
	return holdOf("climb")
end

cues.morning = function(): number
	local def = StageData.rooms.morning
	if viewport == nil or def == nil or not inRoom("lamp", "morning") then
		return 0
	end
	buildRoom(def)
	viewport.Visible = true
	timers.morning = os.clock()
	setVeil(Color3.new(1, 1, 1), 1)
	playCamera("morning")
	return holdOf("morning")
end

cues.scan42 = function(): number
	if not inRoom("morning") then
		return 0
	end
	timers.scan42 = os.clock()
	playCamera("scan42")
	startScan(0.3)
	return holdOf("scan42")
end

cues.take = function(): number
	if not inRoom("lamp") then
		return 0
	end
	timers.take = os.clock()
	playCamera("take")
	return holdOf("take")
end

cues.keep = function(): number
	if not inRoom("lamp") then
		return 0
	end
	timers.keep = os.clock()
	timers.ladder = timers.ladder or (os.clock() - 3)
	playCamera("keep")
	return holdOf("keep")
end

-- The tape cues -------------------------------------------------------------------------------

local function isTape(): boolean
	local def = room
	return def ~= nil and string.sub(def.id, 1, 5) == "tape."
end

cues.reach = function(): number
	local frame = viewport
	if not isTape() or frame == nil or figures.main == nil then
		return 0
	end
	if part("ReachArm") == nil then
		named.ReachArm = newPart(
			frame,
			"ReachArm",
			Vector3.new(0.7, 0.7, 1),
			CFrame.new(),
			(figures.main :: Figure).coat
		)
		named.ReachHand = newPart(
			frame,
			"ReachHand",
			Vector3.new(0.9, 0.9, 0.9),
			CFrame.new(),
			SKIN,
			false,
			Enum.PartType.Ball
		)
		named.ReachArm.Transparency = 1
		named.ReachHand.Transparency = 1
	end
	timers.reach = os.clock()
	return holdOf("reach")
end

cues.static = function(): number
	if not isTape() then
		return 0
	end
	-- the picture dies under the static the player sees (Cutscene draws it)
	timers.dead = os.clock() + 0.45
	return holdOf("static")
end

cues.door = function(): number
	if not isTape() then
		return 0
	end
	local door = part("Door")
	if door then
		door.Transparency = 0
	end
	playCamera("door")
	return holdOf("door")
end

cues.fade = function(): number
	if isTape() then
		fadeGoal = 0.9
	end
	return 0
end

cues.gone = function(): number
	if isTape() then
		fadeGoal = 1
	end
	return 0
end

cues.dim = function(): number
	if isTape() then
		timers.dim = os.clock()
	end
	return 0
end

cues.echo = function(): number
	local frame = viewport
	if not isTape() or frame == nil or figures.extra ~= nil then
		return 0
	end
	local pale = newFigure(frame, "Echo")
	dress(pale, "Echo")
	pale.ghost = 0.45
	setSeeThrough(pale, 0)
	figures.extra = pale
	return 0
end

cues.shape = function(): number
	local frame = viewport
	if not isTape() or frame == nil then
		return 0
	end
	if part("ShapeBody") == nil then
		local black = Color3.fromRGB(6, 6, 8)
		named.ShapeBody =
			newPart(frame, "ShapeBody", Vector3.new(0.4, 0.8, 0.15), CFrame.new(), black)
		named.ShapeHead = newPart(
			frame,
			"ShapeHead",
			Vector3.new(0.3, 0.3, 0.3),
			CFrame.new(),
			black,
			false,
			Enum.PartType.Ball
		)
		named.ShapeArmL =
			newPart(frame, "ShapeArmL", Vector3.new(0.1, 0.7, 0.12), CFrame.new(), black)
		named.ShapeArmR =
			newPart(frame, "ShapeArmR", Vector3.new(0.1, 0.7, 0.12), CFrame.new(), black)
		shapeSize = 0.3
	end
	shapeStep += 1
	return 0
end

--------------------------------------------------------------------------------------------
-- The outside

-- True for a set name Stage can draw ("office", "tape", "lamp").
function Stage.knows(set: string): boolean
	return StageData.roomFor(set, "") ~= nil
end

-- Builds the set into `container` (a GuiObject) with its first shot already in place, and
-- starts the camera. Returns false (and draws nothing) for a set it does not know.
function Stage.open(container: GuiObject, set: string, id: string?, firstSpeaker: string?): boolean
	Stage.close()
	local roomId = StageData.roomFor(set, id or "")
	local def = if roomId then StageData.rooms[roomId] else nil
	if def == nil then
		return false
	end
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Stage"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(16, 17, 20)
	frame.BorderSizePixel = 0
	frame.ZIndex = 1
	viewport = frame
	local view = Instance.new("Camera")
	view.FieldOfView = def.fov
	view.Parent = frame
	frame.CurrentCamera = view
	camera = view
	openedAt = os.clock()
	buildRoom(def)
	if isTape() then
		-- the speaker of a tape: whoever speaks first who is not Theo, in their own colours
		local speaker = firstSpeaker or "Ines"
		if speaker ~= "Announcer" and speaker ~= "Theo" and speaker ~= "Echo" then
			local main = newFigure(frame, speaker)
			dress(main, speaker)
			figures.main = main
			local root = CFrame.lookAt(SPEAKER_SPOT, SPEAKER_SPOT + Vector3.new(0, 0, 1))
			pose(main, root, 0, 0, 0, 0, 0)
		end
	end
	-- the first frame is in place before anything is drawn
	local opening = def.cues[def.start]
	if opening and opening.segs then
		local position, lookAt = StageData.cameraAt(opening.segs, 0)
		view.CFrame = CFrame.lookAt(v3(position), v3(lookAt))
	end
	if def.id == "office" then
		local theo = figures.main
		if theo then
			pose(theo, CFrame.lookAt(THEO_START, Vector3.new(6, 0, -6)), 0, 0, 0, 0, 0)
		end
	end
	frame.Parent = container
	stepConnection = RunService.RenderStepped:Connect(step)
	return true
end

-- A `stage` beat. Returns the seconds the scene should wait before the next beat (0 for a cue
-- that is over at once). Unknown names, and cues for another set, do nothing.
function Stage.run(name: string): number
	if viewport == nil then
		return 0
	end
	local handler = cues[name]
	if handler == nil then
		return 0
	end
	local ok, held = pcall(handler)
	if not ok then
		warn("Stage:", held)
		return 0
	end
	return math.clamp(held :: number, 0, 6)
end

-- A line is starting: the figure on screen talks for about as long as the line takes to type.
function Stage.speak(speaker: string, seconds: number)
	if viewport == nil then
		return
	end
	local until_ = os.clock() + seconds
	local def = room
	if def == nil then
		return
	end
	if isTape() then
		if speaker == "Echo" then
			talkUntil.extra = until_
		elseif speaker ~= "Theo" and speaker ~= "Announcer" then
			local who = figures.main
			if who and who.name ~= speaker then
				dress(who, speaker)
			end
			talkUntil.main = until_
		end
	elseif def.id == "lamp" then
		if speaker == "Ines" then
			talkUntil.main = until_
		elseif speaker == "Theo" then
			talkUntil.second = until_
		end
	elseif speaker == "Theo" then
		talkUntil.main = until_
	end
end

-- Seconds the picture still needs after the last line: the dots of a scan being drawn.
function Stage.settle(): number
	if viewport == nil or dotNext > #dotList then
		return 0
	end
	return math.clamp(dotStart + dotSeconds - os.clock(), 0, 6) + 0.6
end

-- The ViewportFrame being drawn, so a scene's end can fade it with the rest of the screen.
function Stage.frame(): ViewportFrame?
	return viewport
end

function Stage.close()
	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
	if viewport then
		viewport:Destroy()
	end
	viewport = nil
	camera = nil
	room = nil
	named = {}
	resetState()
end

--------------------------------------------------------------------------------------------
-- The portrait: a lit face beside the subtitles of a camp talk

export type Portrait = {
	show: (speaker: string) -> (),
	talk: (seconds: number) -> (),
	close: () -> (),
}

-- Fills `container` with a small ViewportFrame showing whoever speaks, chest up, in their coat.
function Stage.openPortrait(container: GuiObject): Portrait
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Portrait"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	frame.BorderSizePixel = 0
	frame.Ambient = Color3.fromRGB(150, 148, 146)
	frame.LightColor = Color3.fromRGB(255, 240, 222)
	frame.LightDirection = Vector3.new(0.3, -0.4, -1)
	local view = Instance.new("Camera")
	view.FieldOfView = 38
	view.CFrame = CFrame.lookAt(Vector3.new(0, 4.35, 4.6), Vector3.new(0, 4.05, 0))
	view.Parent = frame
	frame.CurrentCamera = view
	frame.Parent = container
	local who = newFigure(frame, "")
	local root = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(0, 0, 1))
	local speakingUntil = 0
	local connection: RBXScriptConnection? = nil
	local alive = true
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local mouth, bob = talk(speakingUntil, now)
		local sway = math.sin(now * 1.3) * 0.03
		pose(who, root * CFrame.Angles(0, sway, 0), 0, 0, bob, mouth, 0)
	end)
	local portrait: Portrait = {
		show = function(speaker: string)
			if alive and who.name ~= speaker then
				dress(who, speaker)
			end
		end,
		talk = function(seconds: number)
			speakingUntil = os.clock() + seconds
		end,
		close = function()
			alive = false
			if connection then
				connection:Disconnect()
				connection = nil
			end
			frame:Destroy()
		end,
	}
	return portrait
end

return Stage
