--!strict
-- The in-play interface: crosshair and spread ring, sweep meter, recorder progress,
-- objectives, Static, toasts, hints, recorder dialogue, the Wayfinder needle and map, title
-- cards, the red aura and the screen fade. Everything here is non-modal and kept to the
-- edges: the dots are the game, the HUD stays out of their way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Avatar = require(script.Parent.Avatar)
local Config = require(ReplicatedStorage.Shared.Config)
local Lidar = require(script.Parent.Lidar)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

type Line = { speaker: string, text: string }

local TOAST_SECONDS = 4.5
local TOAST_LIMIT = 4
local CARD_SECONDS = 4
local METER_WIDTH = 190
local COMPASS_WIDTH = 220
local COMPASS_FOV = 100 -- degrees of bearing the strip spans
local MAP_SIZE = 130
local MAP_HZ = 6
local CELL = Config.World.cellSize
local TYPE_CHARS_PER_SECOND = 48
local LINE_HOLD_MIN = 4 -- seconds a spoken line stays after it has been typed out
local LINE_HOLD_PER_CHAR = 0.045
local LINE_FADE_SECONDS = 0.8
local RING_SHOW_SECONDS = 1.1 -- the spread ring shows this long after the spread changes
local AURA_DEPTH = 0.24 -- share of the screen the aura reaches in from each edge
local AURA_STRENGTH = 0.6

local Hud = {}

local gui: ScreenGui
local fadeGui: ScreenGui
local fadeFrame: Frame
local crosshair: Frame
local meterBack: Frame
local meterFill: Frame
local meterLabel: TextLabel
local deniedAt = 0 -- when a sweep was last asked for with an empty battery
local DENIED_SECONDS = 1.4
local crouchLabel: TextLabel
local spreadRing: Frame
local spreadStroke: UIStroke
local echoBack: Frame
local echoFill: Frame
local dialoguePanel: Frame
local dialogueSpeaker: TextLabel
local dialogueText: TextLabel
local auraEdges: { UIGradient } = {}
local flashFrame: Frame
local tierLabel: TextLabel
local objectiveLabel: TextLabel
local staticLabel: TextLabel
local toastStack: Frame
local hintLabel: TextLabel
local hintPanel: Frame
local compass: Frame
local compassMarker: TextLabel
local map: Frame
local mapCells: { [number]: Frame } = {}
local mapPlayer: Frame
local mapExit: Frame
local cardTitle: TextLabel
local cardSubtitle: TextLabel
local downedPanel: Frame
local downedFill: Frame
local photoLabel: TextLabel
local mapTimer = 0
local mapLarge = false
local hidden = false -- photo mode
local lastSpread = Lidar.spread
local spreadChangedAt = -math.huge
local auraLevel = -1
local lines: { Line } = {}
local speaking = false

local function tween(instance: Instance, seconds: number, goal: { [string]: any })
	TweenService
		:Create(
			instance,
			TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			goal
		)
		:Play()
end

-- A short message at the top of the screen. `kind` is "info", "good" or "warn".
function Hud.toast(text: string, kind: string?)
	local color = if kind == "good"
		then Ui.colors.good
		elseif kind == "warn" then Ui.colors.warn
		else Ui.colors.line
	local children = toastStack:GetChildren()
	local labels = {}
	for _, child in children do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	if #labels >= TOAST_LIMIT then
		labels[1]:Destroy()
	end
	local label = Ui.label({
		Text = text,
		TextColor3 = color,
		TextSize = Ui.text.body,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextTransparency = 1,
		LayoutOrder = os.clock() * 100,
		Parent = toastStack,
	})
	tween(label, 0.25, { TextTransparency = 0 })
	task.delay(TOAST_SECONDS, function()
		if label.Parent then
			tween(label, 0.6, { TextTransparency = 1 })
			task.wait(0.6)
			label:Destroy()
		end
	end)
end

-- A large centred title that fades in and out: level names and room names.
function Hud.titleCard(title: string, subtitle: string)
	cardTitle.Text = string.upper(title)
	cardSubtitle.Text = subtitle
	tween(cardTitle, 0.8, { TextTransparency = 0 })
	tween(cardSubtitle, 1.2, { TextTransparency = 0.15 })
	task.delay(CARD_SECONDS, function()
		if cardTitle.Text == string.upper(title) then
			tween(cardTitle, 1.2, { TextTransparency = 1 })
			tween(cardSubtitle, 1.2, { TextTransparency = 1 })
		end
	end)
end

-- A persistent line of guidance near the bottom; nil hides it.
function Hud.hint(text: string?)
	if text == nil then
		hintPanel.Visible = false
	else
		hintLabel.Text = text
		hintPanel.Visible = true
	end
end

-- Fades the whole screen to black (alpha 1) or back (alpha 0).
function Hud.fade(alpha: number, seconds: number)
	tween(fadeFrame, seconds, { BackgroundTransparency = 1 - alpha })
end

-- Photo mode hides the interface so the dots can be captured on their own.
function Hud.setVisible(visible: boolean)
	gui.Enabled = visible
	hidden = not visible
	crosshair.Visible = visible and State.server.stage ~= "title" and State.server.stage ~= "downed"
end

function Hud.photoNotice(on: boolean)
	photoLabel.Visible = on
end

-- Plays queued recorder lines one at a time: typed out, held, then faded.
local function speakNext()
	local line = table.remove(lines, 1)
	if line == nil then
		speaking = false
		return
	end
	speaking = true
	dialogueSpeaker.Text = string.upper(line.speaker)
	dialogueText.Text = line.text
	dialogueText.MaxVisibleGraphemes = 0
	dialoguePanel.Visible = true
	dialoguePanel.BackgroundTransparency = 0.12
	dialogueSpeaker.TextTransparency = 0
	dialogueText.TextTransparency = 0
	task.spawn(function()
		local length = utf8.len(line.text) or #line.text
		local shown = 0
		while shown < length do
			shown = math.min(length, shown + TYPE_CHARS_PER_SECOND * task.wait())
			dialogueText.MaxVisibleGraphemes = math.floor(shown)
		end
		dialogueText.MaxVisibleGraphemes = -1
		task.wait(math.max(LINE_HOLD_MIN, length * LINE_HOLD_PER_CHAR))
		tween(dialoguePanel, LINE_FADE_SECONDS, { BackgroundTransparency = 1 })
		tween(dialogueSpeaker, LINE_FADE_SECONDS, { TextTransparency = 1 })
		tween(dialogueText, LINE_FADE_SECONDS, { TextTransparency = 1 })
		task.wait(LINE_FADE_SECONDS)
		dialoguePanel.Visible = false
		speakNext()
	end)
end

-- A recorder speaks. Lines queue, so two recorders never talk over each other.
function Hud.dialogue(speaker: string, line: string)
	table.insert(lines, { speaker = speaker, text = line })
	if not speaking then
		speakNext()
	end
end

-- The red glow at the screen edges: 0 is none, 1 is something right beside you. Cheap to
-- call every frame; it only touches the interface when the level actually changes.
function Hud.setAura(level: number)
	level = math.clamp(level, 0, 1)
	if math.abs(level - auraLevel) < 0.01 then
		return
	end
	auraLevel = level
	local edge = 1 - AURA_STRENGTH * level
	local sequence = NumberSequence.new({
		NumberSequenceKeypoint.new(0, edge),
		NumberSequenceKeypoint.new(1, 1),
	})
	for _, gradient in auraEdges do
		gradient.Transparency = sequence
	end
end

-- A quick full-screen tint that fades out.
function Hud.flash(color: Color3, seconds: number)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 0.55
	tween(flashFrame, seconds, { BackgroundTransparency = 1 })
end

local function build()
	gui = Ui.screen("Hud", 10)
	fadeGui = Ui.overlay("Fade", 50)
	fadeFrame = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5, -- above the crosshair, which lives in the same overlay
		Parent = fadeGui,
	})
	photoLabel = Ui.label({
		Text = "DOTS FROZEN",
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -10),
		Size = UDim2.fromOffset(240, 18),
		Visible = false,
		Parent = fadeGui,
	})

	crosshair = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		Parent = fadeGui, -- the overlay ignores insets, so this is the true screen centre
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Ui.new("UIStroke", { Color = Ui.colors.line, Transparency = 0.35, Thickness = 1.2 }),
	})

	-- The red aura: four gradients reaching in from the screen edges.
	for _, edge in
		{
			{
				anchor = Vector2.new(0.5, 0),
				position = UDim2.fromScale(0.5, 0),
				rotation = 90,
				wide = true,
			},
			{
				anchor = Vector2.new(0.5, 1),
				position = UDim2.fromScale(0.5, 1),
				rotation = -90,
				wide = true,
			},
			{
				anchor = Vector2.new(0, 0.5),
				position = UDim2.fromScale(0, 0.5),
				rotation = 0,
				wide = false,
			},
			{
				anchor = Vector2.new(1, 0.5),
				position = UDim2.fromScale(1, 0.5),
				rotation = 180,
				wide = false,
			},
		}
	do
		local gradient = Ui.new("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new(1),
		})
		Ui.new("Frame", {
			AnchorPoint = edge.anchor,
			Position = edge.position,
			Size = if edge.wide
				then UDim2.fromScale(1, AURA_DEPTH)
				else UDim2.fromScale(AURA_DEPTH, 1),
			BackgroundColor3 = Ui.colors.bad,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = fadeGui,
		}, { gradient })
		table.insert(auraEdges, gradient)
	end
	flashFrame = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = fadeGui,
	})

	-- The spread ring: the cone's edge, drawn round the crosshair for a moment after it changes.
	spreadStroke = Ui.new("UIStroke", {
		Color = Ui.colors.line,
		Transparency = 1,
		Thickness = 1,
	})
	spreadRing = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1,
		Parent = fadeGui,
	}, { Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }), spreadStroke })

	-- Progress on a hidden recorder, just under the crosshair.
	echoBack = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 14),
		Size = UDim2.fromOffset(46, 3),
		BackgroundColor3 = Ui.colors.gold,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Visible = false,
		Parent = fadeGui,
	})
	echoFill = Ui.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Ui.colors.gold,
		BorderSizePixel = 0,
		Parent = echoBack,
	})

	-- Sweep meter.
	meterBack = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -34),
		Size = UDim2.fromOffset(METER_WIDTH, 4),
		BackgroundColor3 = Ui.colors.line,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = gui,
	})
	meterFill = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.colors.line,
		BorderSizePixel = 0,
		Parent = meterBack,
	})
	meterLabel = Ui.label({
		Text = "SWEEP",
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(METER_WIDTH, 16),
		Parent = gui,
	})
	crouchLabel = Ui.label({
		Text = "CROUCHED",
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -12),
		Size = UDim2.fromOffset(120, 16),
		Visible = false,
		Parent = gui,
	})

	-- Recorder lines, typed out in the lower third.
	dialoguePanel = Ui.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -160),
		Size = UDim2.fromOffset(460, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	}, { Ui.padding(12), Ui.list(Enum.FillDirection.Vertical, 4) })
	dialogueSpeaker = Ui.label({
		FontFace = Ui.fontBold,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.gold,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
		Parent = dialoguePanel,
	})
	dialogueText = Ui.label({
		TextSize = Ui.text.body,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = dialoguePanel,
	})

	-- Level and objectives, top left.
	local info = Ui.new("Frame", {
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(280, 44), -- stops short of the compass
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Vertical, 2) })
	tierLabel = Ui.label({
		FontFace = Ui.fontBold,
		TextSize = Ui.text.small,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = info,
	})
	objectiveLabel = Ui.label({
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Parent = info,
	})

	staticLabel = Ui.label({
		FontFace = Ui.fontBold,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(200, 18),
		Parent = gui,
	})

	toastStack = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(620, 120),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Vertical, 4) })

	hintPanel = Ui.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96), -- clear of the touch buttons on a phone
		Size = UDim2.fromOffset(360, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	}, { Ui.padding(10) })
	hintLabel = Ui.label({
		TextSize = Ui.text.body,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = hintPanel,
	})

	-- Wayfinder needle.
	compass = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(COMPASS_WIDTH, 22),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Ui.colors.line,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Parent = compass,
	})
	compassMarker = Ui.label({
		Text = "EXIT",
		FontFace = Ui.fontBold,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(60, 18),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = compass,
	})

	-- Wayfinder map: only what has been scanned.
	map = Ui.panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 38),
		Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE),
		ClipsDescendants = true,
		Visible = false,
		Parent = gui,
	})
	mapExit = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Ui.colors.gold,
		BorderSizePixel = 0,
		ZIndex = 3,
		Visible = false,
		Parent = map,
	})
	mapPlayer = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Ui.colors.good,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = map,
	}, { Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	-- Title card.
	cardTitle = Ui.label({
		FontFace = Ui.fontBold,
		TextSize = Ui.text.title,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(800, 44),
		Parent = gui,
	})
	cardSubtitle = Ui.label({
		TextSize = Ui.text.body,
		TextColor3 = Ui.colors.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 36),
		Size = UDim2.fromOffset(800, 22),
		Parent = gui,
	})

	-- Shown while this player is down in co-op.
	downedPanel = Ui.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(440, 74),
		Visible = false,
		Parent = gui,
	}, { Ui.padding(12) })
	Ui.label({
		Text = "YOU ARE DOWN\nA teammate can stand close and scan you to get you up.",
		TextSize = Ui.text.small,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = downedPanel,
	})
	local downedBack = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Ui.colors.line,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Parent = downedPanel,
	})
	downedFill = Ui.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Ui.colors.good,
		BorderSizePixel = 0,
		Parent = downedBack,
	})
end

local function refreshInfo()
	local server = State.server
	local stage = server.stage
	local playing = stage ~= "title"
	crosshair.Visible = playing and stage ~= "downed" and not hidden
	local armed = stage == "level" or stage == "tutorial"
	meterLabel.Visible = armed
	meterBack.Visible = armed
	staticLabel.Visible = playing
	staticLabel.Text = "STATIC " .. State.profile.static
	downedPanel.Visible = stage == "downed"

	if stage == "level" or stage == "downed" then
		local prefix = if server.mode == "daily" then "DAILY SURVEY" else "TIER " .. server.tier
		tierLabel.Text = prefix .. "  " .. string.upper(server.tierName)
		local parts = {}
		if server.locked then
			local gate = if server.gateName ~= "" then string.upper(server.gateName) else "KEY"
			local key = if server.hasKey
				then `<font color="#60f08c">{gate} FOUND</font>`
				else `{gate} NEEDED`
			table.insert(parts, key)
		end
		if server.cellsTotal > 0 then
			table.insert(parts, `CELLS {server.cells}/{server.cellsTotal}`)
		end
		if server.rescuesTotal > 0 then
			table.insert(parts, `SURVEYORS {server.rescues}/{server.rescuesTotal}`)
		end
		if server.echoesTotal > 0 then
			table.insert(parts, `HIDDEN {server.echoes}/{server.echoesTotal}`)
		end
		objectiveLabel.Text = table.concat(parts, "   ")
	elseif stage == "tutorial" then
		tierLabel.Text = "INTAKE"
		objectiveLabel.Text = "FIND THE WAY OUT"
	else
		tierLabel.Text = ""
		objectiveLabel.Text = ""
	end
end

local function mapCell(index: number): Frame
	local cell = mapCells[index]
	if cell == nil then
		cell = Ui.new("Frame", {
			BackgroundColor3 = Ui.colors.line,
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Parent = map,
		})
		mapCells[index] = cell
	end
	return cell
end

local function refreshMap()
	local plan = State.plan
	local show = plan ~= nil and State.inLevel() and State.effects.wayfinder >= 2
	map.Visible = show
	if not show or plan == nil then
		return
	end
	local size = if mapLarge then MAP_SIZE * 2 else MAP_SIZE
	map.Size = UDim2.fromOffset(size, size)
	local maze = plan.maze
	local unit = size / math.max(maze.width, maze.height)
	for index in State.scannedCells do
		local where = Maze.cellAt(maze, index)
		local cell = mapCell(index)
		-- Shrink each side that has a wall, so corridors and openings read at a glance.
		local left = if Maze.isOpen(maze, where.x, where.y, "W") then 0 else 1
		local right = if Maze.isOpen(maze, where.x, where.y, "E") then 0 else 1
		local top = if Maze.isOpen(maze, where.x, where.y, "N") then 0 else 1
		local bottom = if Maze.isOpen(maze, where.x, where.y, "S") then 0 else 1
		cell.Position = UDim2.fromOffset((where.x - 1) * unit + left, (where.y - 1) * unit + top)
		cell.Size = UDim2.fromOffset(unit - left - right, unit - top - bottom)
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		local relative = (root.Position - State.server.origin) / CELL
		mapPlayer.Position = UDim2.fromOffset(relative.X * unit, relative.Z * unit)
	end
	mapExit.Visible = State.exitScanned
	mapExit.Position = UDim2.fromOffset((maze.exit.x - 0.5) * unit, (maze.exit.y - 0.5) * unit)
end

local function refreshCompass()
	local plan = State.plan
	local camera = workspace.CurrentCamera
	local show = plan ~= nil
		and camera ~= nil
		and State.inLevel()
		and State.effects.wayfinder >= 1
		and State.exitScanned
	compass.Visible = show
	if not show or plan == nil or camera == nil then
		return
	end
	local exit = State.server.origin
		+ Vector3.new((plan.maze.exit.x - 0.5) * CELL, 0, (plan.maze.exit.y - 0.5) * CELL)
	local toExit = (exit - camera.CFrame.Position) * Vector3.new(1, 0, 1)
	local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	if toExit.Magnitude < 1 or look.Magnitude < 0.01 then
		return
	end
	local bearing = math.deg(math.atan2(look.Unit:Cross(toExit.Unit).Y, look.Unit:Dot(toExit.Unit)))
	-- Roblox's Y-up cross product is positive when the target is to the left.
	local offset = math.clamp(-bearing / (COMPASS_FOV / 2), -1, 1)
	compassMarker.Position = UDim2.new(0.5 + offset * 0.5, 0, 0.5, 0)
	compassMarker.Text = if math.abs(offset) >= 1
		then (if offset < 0 then "< EXIT" else "EXIT >")
		else "EXIT"
end

-- The cone's edge on screen: its radius in pixels is the share of the view's half-height
-- that the spread's half-angle covers.
local function refreshSpreadRing(camera: Camera?)
	local now = os.clock()
	if Lidar.spread ~= lastSpread then
		lastSpread = Lidar.spread
		spreadChangedAt = now
	end
	local age = now - spreadChangedAt
	if camera == nil or age > RING_SHOW_SECONDS or hidden then
		spreadStroke.Transparency = 1
		return
	end
	local halfHeight = camera.ViewportSize.Y / 2
	local radius = halfHeight
		* math.tan(math.rad(Lidar.spread))
		/ math.tan(math.rad(camera.FieldOfView / 2))
	spreadRing.Size = UDim2.fromOffset(radius * 2, radius * 2)
	spreadStroke.Transparency = 0.45 + 0.55 * (age / RING_SHOW_SECONDS) ^ 2
end

local function update(dt: number)
	-- The meter holds the battery: one share per charge, plus the Trickle Charger's progress.
	local capacity = math.max(1, State.effects.chargeCapacity)
	local free = Lidar.freeSweeps
	local fill = if free then 1 else math.min(1, (Lidar.charges + Lidar.trickle) / capacity)
	meterFill.Size = UDim2.fromScale(fill, 1)
	local ready = Lidar.charge >= 1
	local denied = os.clock() - deniedAt < DENIED_SECONDS
	meterFill.BackgroundColor3 = if Lidar.sweeping
		then Ui.colors.warn
		elseif ready then Ui.colors.line
		else Ui.colors.dim
	meterLabel.Text = if Lidar.sweeping
		then "SWEEPING"
		elseif free then "SWEEP READY"
		elseif Lidar.charges >= 1 then `SWEEP {Lidar.charges}/{capacity}`
		else "SWEEP 0 - FIND A CELL"
	meterLabel.TextColor3 = if denied
		then Ui.colors.warn
		elseif ready and not Lidar.sweeping then Ui.colors.line
		else Ui.colors.dim
	crouchLabel.Visible = Avatar.crouching and not hidden

	local camera = workspace.CurrentCamera
	refreshSpreadRing(camera)
	echoBack.Visible = Lidar.echoProgress > 0 and not hidden
	echoFill.Size = UDim2.fromScale(Lidar.echoProgress, 1)

	refreshCompass()
	mapTimer -= dt
	if mapTimer <= 0 then
		mapTimer = 1 / MAP_HZ
		refreshMap()
	end

	if State.server.stage == "downed" then
		local character = Players.LocalPlayer.Character
		local progress = if character then character:GetAttribute("Revive") else nil
		downedFill.Size =
			UDim2.fromScale(math.clamp(if type(progress) == "number" then progress else 0, 0, 1), 1)
	end
end

-- The story's card for the floor a level is on: the daily floor, a Relay floor past the
-- authored tiers, or the section (B3 The Annex, and so on).
local function levelCard(server: State.ServerState): (string, string)
	if server.mode == "daily" then
		return Lore.dailyCard.title, Lore.dailyCard.subtitle
	end
	local section = Lore.sectionFor(server.tier)
	if section == nil then
		return server.tierName, Lore.relayCard.subtitle
	end
	return section.card.title, section.floor .. "  /  " .. section.card.subtitle
end

function Hud.toggleMap()
	mapLarge = not mapLarge
end

function Hud.start()
	build()
	refreshInfo()
	Lidar.onDenied(function()
		deniedAt = os.clock()
	end)
	State.onState(function(server, previous)
		refreshInfo()
		if
			server.stage == "level"
			and (
				server.seed ~= previous.seed
				or previous.stage ~= "level" and previous.stage ~= "downed"
			)
		then
			Hud.titleCard(levelCard(server))
		end
	end)
	State.onProfile(refreshInfo)
	State.onLevel(function()
		for _, cell in mapCells do
			cell:Destroy()
		end
		table.clear(mapCells)
	end);
	(Net.get("Toast") :: RemoteEvent).OnClientEvent:Connect(Hud.toast)
	RunService.RenderStepped:Connect(update)
end

return Hud
