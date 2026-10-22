--!strict
-- Moments: being caught, pickups, pings and emotes between teammates, the rescued surveyor's
-- trail to the exit, hidden recorders speaking, alarm plates and pits, anomaly rooms, photo
-- mode, and haptics. Each is small; together they are most of what makes a run feel alive.

local CollectionService = game:GetService("CollectionService")
local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(script.Parent.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local DotRules = require(ReplicatedStorage.Shared.pure.DotRules)
local Dots = require(script.Parent.Dots)
local Enemies = require(ReplicatedStorage.Shared.data.Enemies)
local Hud = require(script.Parent.Hud)
local Input = require(script.Parent.Input)
local Lidar = require(script.Parent.Lidar)
local Lore = require(ReplicatedStorage.Shared.data.Lore)
local Maze = require(ReplicatedStorage.Shared.pure.Maze)
local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

type Marker = { model: Model, expires: number, parts: { Part } }

local CELL = Config.World.cellSize
local PING_RING = 14 -- dots in a ping marker's ring
local PING_RADIUS = 1.6
local PING_COLUMN = 8
local PING_FADE_SECONDS = 2
local EMOTE_SECONDS = 3.5
local TRAIL_DOTS_PER_CELL = 5
local TRAIL_STEP_SECONDS = 0.28 -- five steps a cell: about walking pace
local FOOT_SPREAD = 0.35
local WALKER_HEIGHTS = { 0.6, 1.6, 2.6, 3.4, 4.1, 4.8 } -- legs to head
local WALKER_DOT_SIZE = 0.1
local WALKER_HEAD_SIZE = 0.22
local WALKER_WIDTH = 0.7
local WALKER_LIFETIME = 0.7
local STAND_PULSES = 6
-- What a surveyor says once helped up. The tapping line is how you tell them from the Mimic.
local SURVEYOR_LINES = {
	"Two taps, then one. That's us. Anything that sits still and doesn't tap isn't.",
	"Thought the lamp had given up on me. Stairs are this way.",
	"Don't help up the quiet ones. Come on, I know the way.",
}
local TRAIL_HEIGHT = 0.3
local TRAIL_SIZE = 0.14
local TRAIL_LIFETIME = 40 -- seconds: long enough to follow it to the door
local SHAKE_SECONDS = 0.35
local SHAKE_STRENGTH = 0.5
local MIRROR_HEIGHT = 5
local ZONE_HZ = 6

local Effects = {}

local player = Players.LocalPlayer
local markers: { Marker } = {}
local markerFolder = Instance.new("Folder")
markerFolder.Name = "LidarMarkers"
local shakeUntil = 0
local bloomed: { [Instance]: boolean } = {}
local reflection: Model? = nil
local zoneTimer = 0
local zoneParams = RaycastParams.new()
zoneParams.FilterType = Enum.RaycastFilterType.Exclude

--------------------------------------------------------------------------------------------
-- Haptics

-- A short rumble on gamepads and, where the device supports it, on phones.
function Effects.pulse(strength: number, seconds: number)
	task.spawn(function()
		pcall(function()
			if HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1) then
				HapticService:SetMotor(
					Enum.UserInputType.Gamepad1,
					Enum.VibrationMotor.Large,
					strength
				)
				task.wait(seconds)
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
			end
		end)
	end)
	if Input.device == "touch" then
		pcall(function()
			local effect = Instance.new("HapticEffect")
			effect.Type = Enum.HapticEffectType.GameplayCollision
			effect.Parent = workspace
			effect:Play()
			task.delay(1, function()
				effect:Destroy()
			end)
		end)
	end
end

--------------------------------------------------------------------------------------------
-- Caught and revived

local function onCaught(enemyKind: string, downed: boolean)
	Input.releaseAll()
	Audio.caught()
	Effects.pulse(1, 0.4)
	shakeUntil = os.clock() + SHAKE_SECONDS
	local def = Enemies[enemyKind]
	local entity = Lore.entities[enemyKind]
	if def then
		local name = if entity then entity.name else def.displayName
		Hud.toast("Caught by " .. name .. ".", "warn")
		Hud.toast(def.rule, "info")
	end
	if downed then
		Hud.fade(0.55, 0.3)
	else
		Hud.fade(1, 0.2)
		task.delay(Config.World.respawnSeconds + 0.2, function()
			Hud.fade(0, 0.9)
		end)
	end
end

local function onRevived()
	Hud.fade(0, 0.6)
	Audio.pickup()
end

--------------------------------------------------------------------------------------------
-- Pings and emotes

local function neon(parent: Instance, position: Vector3, size: number, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Size = Vector3.one * size
	part.Color = color
	part.Position = position
	part.Parent = parent
	return part
end

local function onPingMarker(_userId: number, position: Vector3, lifetime: number)
	local model = Instance.new("Model")
	model.Name = "Ping"
	local parts: { Part } = {}
	local color = Dots.color("objective")
	for index = 1, PING_RING do
		local angle = index / PING_RING * math.pi * 2
		local offset =
			Vector3.new(math.cos(angle) * PING_RADIUS, 0.2, math.sin(angle) * PING_RADIUS)
		table.insert(parts, neon(model, position + offset, 0.22, color))
	end
	for index = 1, PING_COLUMN do
		table.insert(parts, neon(model, position + Vector3.new(0, index * 0.9, 0), 0.18, color))
	end
	model.Parent = markerFolder
	table.insert(markers, { model = model, expires = os.clock() + lifetime, parts = parts })
	Audio.sequence({ 1.6, 1.6 }, 0.1, 0.35)
end

local function sendPing()
	local camera = workspace.CurrentCamera
	if camera == nil or State.server.stage ~= "level" then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = { Dots.folder(), markerFolder }
	if player.Character then
		table.insert(excluded, player.Character)
	end
	params.FilterDescendantsInstances = excluded
	local result = workspace:Raycast(
		camera.CFrame.Position,
		camera.CFrame.LookVector * Config.Lidar.maxRange,
		params
	)
	if result then
		(Net.get("Ping") :: RemoteEvent):FireServer(result.Position)
	end
end

local function onEmote(userId: number, index: number)
	local other = Players:GetPlayerByUserId(userId)
	local word = Config.Coop.emotes[index]
	local head = if other and other.Character then other.Character:FindFirstChild("Head") else nil
	if other == nil or word == nil then
		return
	end
	if other == player or head == nil then
		Hud.toast(other.DisplayName .. ": " .. word, "info")
		return
	end
	local billboard = Ui.new("BillboardGui", {
		Name = "Emote",
		Size = UDim2.fromOffset(160, 36),
		StudsOffset = Vector3.new(0, 2.6, 0),
		AlwaysOnTop = true,
		MaxDistance = 220,
		Adornee = head,
		Parent = head,
	}, {
		Ui.label({
			Text = string.upper(word),
			FontFace = Ui.fontBold,
			TextSize = Ui.text.large,
			TextColor3 = Ui.colors.good,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
		}),
	})
	Audio.blip(2.1, 0.3)
	task.delay(EMOTE_SECONDS, function()
		billboard:Destroy()
	end)
end

--------------------------------------------------------------------------------------------
-- Objectives

-- A rescued surveyor stands up and walks the shortest route to the exit: a short-lived green
-- figure of dots moves at walking pace and leaves footprints that stay long enough to follow.
local function drawWalker(position: Vector3)
	for index, height in WALKER_HEIGHTS do
		local size = if index == #WALKER_HEIGHTS then WALKER_HEAD_SIZE else WALKER_DOT_SIZE
		local jitter = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * WALKER_WIDTH
		Dots.mark(position + jitter + Vector3.new(0, height, 0), "friend", size, WALKER_LIFETIME)
	end
end

local function drawTrail(from: Vector3)
	local plan = State.plan
	if plan == nil then
		return
	end
	local maze = plan.maze
	local origin = State.server.origin
	local relative = (from - origin) / CELL
	local route = Maze.path(maze, Maze.cellOf(maze, relative.X, relative.Z), maze.exit)
	local previous = Vector3.new(relative.X, 0, relative.Z)
	local seed = plan.seed
	task.spawn(function()
		-- Getting up: the figure stands where it sat for a moment before it sets off.
		for _ = 1, STAND_PULSES do
			drawWalker(Vector3.new(from.X, origin.Y, from.Z))
			task.wait(TRAIL_STEP_SECONDS)
		end
		Hud.dialogue("Surveyor", SURVEYOR_LINES[math.random(#SURVEYOR_LINES)])
		for _, cell in route do
			local target = Vector3.new(cell.x - 0.5, 0, cell.y - 0.5)
			for step = 1, TRAIL_DOTS_PER_CELL do
				if State.plan == nil or State.plan.seed ~= seed then
					return -- the level changed under us
				end
				local point = previous:Lerp(target, step / TRAIL_DOTS_PER_CELL) * CELL
				local foot = origin + Vector3.new(point.X, 0, point.Z)
				local side = if step % 2 == 0 then FOOT_SPREAD else -FOOT_SPREAD
				Dots.mark(
					foot + Vector3.new(side, TRAIL_HEIGHT, 0),
					"friend",
					TRAIL_SIZE,
					TRAIL_LIFETIME
				)
				drawWalker(foot)
				task.wait(TRAIL_STEP_SECONDS)
			end
			previous = target
		end
	end)
end

local function onObjective(kind: string, detail: { position: Vector3, by: number })
	Effects.pulse(0.4, 0.15)
	if kind == "exit" then
		Audio.door()
		return
	end
	Audio.pickup()
	if kind == "cell" then
		Lidar.recharge()
	elseif kind == "rescue" then
		drawTrail(detail.position)
	end
end

--------------------------------------------------------------------------------------------
-- Recorders and hazards

-- A hidden recorder revealed itself: its line is spoken to everyone in the level.
local function onEcho(
	_echoId: number,
	position: Vector3,
	speaker: string,
	line: string,
	thought: string?
)
	Audio.echo(position)
	if speaker ~= "" then
		Effects.pulse(0.25, 0.1) -- a tape starts; a poster or a lamp-bag tag just says its words
	end
	Hud.dialogue(speaker, line)
	if thought ~= nil and thought ~= "" then
		State.storyLive = true
		Hud.dialogue("Theo", thought)
	end
end

local function onHazard(kind: string, position: Vector3, userId: number)
	local mine = userId == player.UserId
	if kind == "plate" then
		Audio.alarm(position)
		if mine then
			Hud.flash(Dots.color("hazard"), 0.6)
			Effects.pulse(0.6, 0.25)
		end
	elseif kind == "pit" and mine then
		-- The server has already put us back at the start; cover the jump with a fall.
		Input.releaseAll()
		Audio.fall()
		Effects.pulse(0.8, 0.3)
		Hud.fade(1, 0.1)
		task.delay(0.7, function()
			Hud.fade(0, 0.9)
		end)
	end
end

--------------------------------------------------------------------------------------------
-- Anomaly rooms

local function inside(zone: BasePart, position: Vector3): boolean
	local localPosition = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPosition.X) <= half.X
		and math.abs(localPosition.Y) <= half.Y
		and math.abs(localPosition.Z) <= half.Z
end

-- Bloom: the room fills with dots nobody fired, once.
local function bloom(zone: BasePart)
	local settings = Config.Anomaly
	local perStep = math.ceil(settings.bloomDots / (settings.bloomSeconds * 30))
	local excluded: { Instance } = { Dots.folder(), markerFolder }
	if player.Character then
		table.insert(excluded, player.Character)
	end
	zoneParams.FilterDescendantsInstances = excluded
	Audio.sequence({ 0.7, 0.8, 0.9, 1.0, 1.2 }, 0.3, 0.3)
	task.spawn(function()
		local remaining = settings.bloomDots
		while remaining > 0 and zone.Parent ~= nil do
			for _ = 1, perStep do
				local half = zone.Size / 2
				local start = zone.Position
					+ Vector3.new(
						(math.random() - 0.5) * half.X,
						(math.random() - 0.5) * half.Y * 0.5,
						(math.random() - 0.5) * half.Z
					)
				local direction =
					Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				if direction.Magnitude > 0.05 then
					local hit = workspace:Raycast(start, direction.Unit * 60, zoneParams)
					if hit and inside(zone, hit.Position + hit.Normal * 0.5) then
						local kind = DotRules.classify({}, hit.Normal.Y)
						Dots.add(hit.Position + hit.Normal * 0.04, kind, hit.Distance)
					end
				end
				remaining -= 1
			end
			task.wait(1 / 30)
		end
	end)
end

-- Mirror: a figure on the far side of the room that stands where you would, if the room
-- were a mirror. It only exists for you, it is invisible like everything else, and it
-- scans green.
local function updateReflection(zone: BasePart?, root: BasePart?)
	if zone == nil or root == nil then
		if reflection then
			reflection:Destroy()
			reflection = nil
		end
		return
	end
	local figure = reflection
	if figure == nil then
		figure = Instance.new("Model")
		figure.Name = "Reflection"
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(2, MIRROR_HEIGHT, 1)
		body.Anchored = true
		body.CanCollide = false
		body.CanTouch = false
		body.CastShadow = false
		body.Transparency = 1
		body.Parent = figure
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.one * 1.2
		head.Anchored = true
		head.CanCollide = false
		head.CanTouch = false
		head.CastShadow = false
		head.Transparency = 1
		head.Parent = figure
		CollectionService:AddTag(figure, Config.Tags.friend)
		figure.Parent = workspace
		reflection = figure
	end
	-- Reflect across the plane through the room's centre, perpendicular to its long side.
	local alongX = zone.Size.X >= zone.Size.Z
	local offset = root.Position - zone.Position
	local mirrored = if alongX
		then Vector3.new(-offset.X, offset.Y, offset.Z)
		else Vector3.new(offset.X, offset.Y, -offset.Z)
	local position = zone.Position + mirrored
	local body = figure:FindFirstChild("Body") :: Part
	local head = figure:FindFirstChild("Head") :: Part
	body.Position = Vector3.new(position.X, root.Position.Y - 0.4, position.Z)
	head.Position = body.Position + Vector3.new(0, MIRROR_HEIGHT / 2 + 0.5, 0)
end

local function updateZones()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local mirrorZone: BasePart? = nil
	if root and root:IsA("BasePart") and State.inLevel() then
		for _, zone in CollectionService:GetTagged(Config.Tags.anomaly) do
			if zone:IsA("BasePart") and inside(zone, root.Position) then
				local kind = zone:GetAttribute("Kind")
				if kind == "bloom" and not bloomed[zone] then
					bloomed[zone] = true
					bloom(zone)
				elseif kind == "mirror" then
					mirrorZone = zone
				end
			end
		end
	end
	updateReflection(mirrorZone, if root and root:IsA("BasePart") then root else nil)
end

--------------------------------------------------------------------------------------------

local function update(dt: number)
	local now = os.clock()
	for index = #markers, 1, -1 do
		local marker = markers[index]
		local remaining = marker.expires - now
		if remaining <= 0 then
			marker.model:Destroy()
			table.remove(markers, index)
		elseif remaining < PING_FADE_SECONDS then
			for _, part in marker.parts do
				part.Transparency = 1 - remaining / PING_FADE_SECONDS
			end
		end
	end

	if now < shakeUntil then
		local camera = workspace.CurrentCamera
		if camera then
			local strength = SHAKE_STRENGTH * (shakeUntil - now) / SHAKE_SECONDS
			camera.CFrame *= CFrame.new(
				(math.random() - 0.5) * strength,
				(math.random() - 0.5) * strength,
				0
			)
		end
	end

	zoneTimer -= dt
	if zoneTimer <= 0 then
		zoneTimer = 1 / ZONE_HZ
		updateZones()
	end
end

local function togglePhoto()
	local frozen = not Dots.isFrozen()
	Dots.setFrozen(frozen)
	Hud.setVisible(not frozen)
	Hud.photoNotice(frozen)
end

function Effects.start()
	markerFolder.Parent = workspace
	Lidar.ignore(markerFolder);
	(Net.get("Caught") :: RemoteEvent).OnClientEvent:Connect(onCaught);
	(Net.get("Revived") :: RemoteEvent).OnClientEvent:Connect(onRevived);
	(Net.get("PingMarker") :: RemoteEvent).OnClientEvent:Connect(onPingMarker);
	(Net.get("EmoteShown") :: RemoteEvent).OnClientEvent:Connect(onEmote);
	(Net.get("Objective") :: RemoteEvent).OnClientEvent:Connect(onObjective);
	(Net.get("Echo") :: RemoteEvent).OnClientEvent:Connect(onEcho);
	(Net.get("Hazard") :: RemoteEvent).OnClientEvent:Connect(onHazard)
	Input.onAction("ping", sendPing)
	Input.onAction("photo", togglePhoto)
	Input.onAction("map", Hud.toggleMap)
	State.onLevel(function()
		table.clear(bloomed)
		for _, marker in markers do
			marker.model:Destroy()
		end
		table.clear(markers)
		Dots.clear()
	end)
	RunService:BindToRenderStep("LidarEffects", Enum.RenderPriority.Camera.Value + 3, update)
end

return Effects
