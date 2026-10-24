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
	Hollis = Color3.fromRGB(88, 90, 104),
	Tobi = Color3.fromRGB(128, 62, 62),
	Ravi = Color3.fromRGB(60, 92, 142),
	Quill = Color3.fromRGB(94, 72, 114),
	Echo = Color3.fromRGB(206, 206, 214),
}
local DEFAULT_FIGURE = Color3.fromRGB(110, 110, 110)
local WALLPAPER = Color3.fromRGB(176, 156, 88)
local MELTED = Color3.fromRGB(214, 176, 74)
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
local melt: { panel: Part?, drips: { Part }, progress: number } =
	{ panel = nil, drips = {}, progress = 0 }

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
	local floorColor = Color3.fromRGB(58, 56, 48)
	newPart("Floor", Vector3.new(40, 1, 70), CFrame.new(0, -0.5, 0), floorColor)
	newPart("WallBack", Vector3.new(40, 14, 1), CFrame.new(0, 7, -26), WALLPAPER)
	newPart("WallL", Vector3.new(1, 14, 70), CFrame.new(-20, 7, 0), WALLPAPER)
	newPart("WallR", Vector3.new(1, 14, 70), CFrame.new(20, 7, 0), WALLPAPER)
	newPart("Pillar", Vector3.new(2, 14, 2), CFrame.new(-8, 7, 6), Color3.fromRGB(150, 134, 80))
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
		lighting(Color3.fromRGB(78, 80, 88), Color3.fromRGB(150, 150, 160))
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
					if on then Color3.fromRGB(78, 80, 88) else Color3.fromRGB(8, 8, 10),
					if on then Color3.fromRGB(150, 150, 160) else Color3.fromRGB(10, 10, 12)
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
		lighting(Color3.fromRGB(52, 44, 26), Color3.fromRGB(120, 98, 56))
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

local function buildTape()
	newPart("Floor", Vector3.new(40, 1, 40), CFrame.new(0, -0.5, 0), Color3.fromRGB(34, 40, 38))
	newPart("WallBack", Vector3.new(40, 16, 1), CFrame.new(0, 8, -12), Color3.fromRGB(52, 62, 58))
	newPart(
		"Map",
		Vector3.new(13, 8, 0.3),
		CFrame.new(0, 7.5, -11.4),
		Color3.fromRGB(196, 188, 160)
	)
	for index = 1, 6 do
		newPart(
			"MapLine",
			Vector3.new(2 + (index % 3) * 2.2, 0.12, 0.2),
			CFrame.new(-3 + (index % 4) * 1.8, 4.8 + index * 0.9, -11.2)
				* CFrame.Angles(0, 0, math.rad(index * 11 - 30)),
			Color3.fromRGB(120, 60, 50)
		)
	end
	newPart("Desk", Vector3.new(9, 3, 3.6), CFrame.new(0, 1.5, -3.5), Color3.fromRGB(86, 66, 46))
	newPart(
		"LampBase",
		Vector3.new(0.9, 0.3, 0.9),
		CFrame.new(3.4, 3.15, -3.2),
		Color3.fromRGB(40, 70, 52)
	)
	newPart(
		"LampStem",
		Vector3.new(0.2, 1.6, 0.2),
		CFrame.new(3.4, 4, -3.2),
		Color3.fromRGB(40, 70, 52)
	)
	newPart(
		"LampShade",
		Vector3.new(0.6, 1.6, 1.6),
		CFrame.new(3.4, 4.9, -3.2) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(34, 96, 66),
		nil,
		Enum.PartType.Cylinder
	)
	newPart(
		"LampBulb",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(3.4, 4.5, -3.2),
		Color3.fromRGB(255, 226, 150),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	newPart(
		"Papers",
		Vector3.new(1.8, 0.1, 1.3),
		CFrame.new(-2.4, 3.1, -3),
		Color3.fromRGB(226, 220, 200)
	)
end

local function runTape(name: string)
	if name == "tape" or name == "start" then
		token += 1
		lighting(Color3.fromRGB(96, 104, 92), Color3.fromRGB(210, 196, 150))
		aim(
			Vector3.new(0, 4.6, 9),
			Vector3.new(0, 4.5, -5),
			Vector3.new(-0.6, 4.9, 7),
			Vector3.new(0, 4.5, -5),
			40
		)
		camRoll = math.rad(2.5)
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
	end
end

-- Builds the set into `container` (a Frame) and starts the camera. `set` is "office" or "tape".
function Stage.open(container: GuiObject, set: string)
	Stage.close()
	setName = set
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Stage"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
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
	melt = { panel = nil, drips = {}, progress = 0 }
	if set == "tape" then
		buildTape()
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
	if setName == "tape" and speaker ~= "Theo" then
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
	melt = { panel = nil, drips = {}, progress = 0 }
	talkUntil = 0
end

return Stage
