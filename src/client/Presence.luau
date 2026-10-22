--!strict
-- How the invisible give themselves away. Monsters cannot be seen and a scan only glimpses
-- them, so they are sensed instead:
--  * Footprints: every few studs a monster walks it leaves a small red print on the floor
--    that fades over several seconds (with a footstep sound), and teammates leave green ones.
--  * Breath: close to a monster, pale mist puffs where its head would be.
--  * The aura: a red glow creeps in at the edges of the screen as one gets near.
--  * Teammates' names float over them and show through walls, so a party can always regroup.
-- A Mimic that is still pretending to be one of ours does none of this: it sits still and
-- holds its breath.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(script.Parent.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Dots = require(script.Parent.Dots)
local Hud = require(script.Parent.Hud)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

type Walker = {
	root: BasePart,
	kind: string, -- a monster's Kind, or "player"
	model: Model,
	last: Vector3?, -- where the previous print was placed
	left: boolean, -- which foot is next
	headHeight: number, -- studs above the root where breath appears
	nextMist: number,
}
type Marker = { gui: BillboardGui, label: TextLabel }

local tracks = Config.Tracks
local PRINT_SIZE = 0.16
local PRINT_SIDE = 0.4 -- studs either side of the walking line
local FLOOR_PROBE = 8 -- studs down from the root to find the floor
local FLOOR_LIFT = 0.04
local PLAYER_HEAD_HEIGHT = 2.6 -- a character's root sits about this far below its head
local MIST_DOTS = 4
local MIST_SPREAD = 0.45
local MIST_SIZE = 0.07
local MIST_LIFETIME = 1.1
local AURA_BLEND = 4
local AURA_CURVE = 1.6 -- above 1 the glow stays faint until something is quite close

local Presence = {}

local player = Players.LocalPlayer
local monsters: { [Model]: Walker } = {}
local mates: { [Player]: Walker } = {}
local markers: { [Player]: Marker } = {}
local aura = 0
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude

local function headHeightOf(model: Model): number
	local ok, size = pcall(function()
		return model:GetExtentsSize()
	end)
	return if ok then math.max(1, size.Y - 0.5) else 5
end

local function watchMonster(instance: Instance)
	if not instance:IsA("Model") or monsters[instance] ~= nil then
		return
	end
	local root = instance.PrimaryPart or instance:WaitForChild("Root", 5)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local kind = instance:GetAttribute("Kind")
	monsters[instance] = {
		root = root,
		kind = if type(kind) == "string" then kind else "",
		model = instance,
		last = nil,
		left = false,
		headHeight = headHeightOf(instance),
		nextMist = 0,
	}
end

-- Drops a print on the floor under `position`, offset to one side of the walking line.
local function placePrint(walker: Walker, position: Vector3, heading: Vector3): Vector3?
	local side = Vector3.new(-heading.Z, 0, heading.X)
		* PRINT_SIDE
		* (if walker.left then 1 else -1)
	walker.left = not walker.left
	local start = position + side + Vector3.new(0, 1, 0)
	local hit = workspace:Raycast(start, Vector3.new(0, -FLOOR_PROBE, 0), floorParams)
	if hit == nil then
		return nil
	end
	local spot = hit.Position + hit.Normal * FLOOR_LIFT
	Dots.mark(
		spot,
		if walker.kind == "player" then "friend" else "enemy",
		PRINT_SIZE,
		tracks.lifetime
	)
	return spot
end

-- Places the next print once the walker has covered a stride since the last one.
local function stepWalker(walker: Walker, groundPosition: Vector3, camera: Vector3)
	local last = walker.last
	if last == nil then
		walker.last = groundPosition
		return
	end
	local moved = (groundPosition - last) * Vector3.new(1, 0, 1)
	if moved.Magnitude < tracks.stride then
		return
	end
	walker.last = groundPosition
	if (groundPosition - camera).Magnitude > tracks.range then
		return
	end
	local spot = placePrint(walker, groundPosition, moved.Unit)
	if spot ~= nil and walker.kind ~= "player" then
		Audio.monsterStep(walker.kind, spot)
	end
end

local function breathe(walker: Walker, now: number)
	if now < walker.nextMist then
		return
	end
	walker.nextMist = now + tracks.mistInterval * (0.8 + math.random() * 0.4)
	local mouth = walker.root.Position + Vector3.new(0, walker.headHeight, 0)
	for _ = 1, MIST_DOTS do
		local drift = Vector3.new(
			(math.random() - 0.5) * MIST_SPREAD,
			(math.random() - 0.5) * MIST_SPREAD * 0.5,
			(math.random() - 0.5) * MIST_SPREAD
		)
		Dots.mark(mouth + drift, "wall", MIST_SIZE, MIST_LIFETIME * (0.7 + math.random() * 0.6))
	end
end

local function refreshFilter()
	local list: { Instance } = { Dots.folder() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	for model in monsters do
		table.insert(list, model)
	end
	floorParams.FilterDescendantsInstances = list
end

local function markerFor(other: Player): Marker?
	local character = other.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if head == nil or not head:IsA("BasePart") then
		return nil
	end
	local marker = markers[other]
	if marker ~= nil and marker.gui.Adornee == head then
		return marker
	end
	if marker ~= nil then
		marker.gui:Destroy()
	end
	local label = Ui.label({
		Text = other.DisplayName,
		FontFace = Ui.fontBold,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.good,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	})
	local gui = Ui.new("BillboardGui", {
		Name = "LidarMarker",
		Size = UDim2.fromOffset(160, 20),
		StudsOffset = Vector3.new(0, 1.8, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = Config.Coop.markerDistance,
		Adornee = head,
		Parent = head,
	}, { label })
	marker = { gui = gui, label = label }
	markers[other] = marker
	return marker
end

local function updateMates(camera: Vector3, playing: boolean)
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local character = other.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if character == nil or root == nil or not root:IsA("BasePart") then
			continue
		end
		local marker = markerFor(other)
		if marker then
			marker.gui.Enabled = playing
			local downed = character:GetAttribute("Downed") == true
			marker.label.Text = if downed then other.DisplayName .. "  DOWN" else other.DisplayName
			marker.label.TextColor3 = if downed then Ui.colors.warn else Ui.colors.good
		end
		local walker = mates[other]
		if walker == nil or walker.root ~= root then
			walker = {
				root = root,
				kind = "player",
				model = character,
				last = nil,
				left = false,
				headHeight = PLAYER_HEAD_HEIGHT,
				nextMist = 0,
			}
			mates[other] = walker
		end
		if playing and character:GetAttribute("Downed") ~= true then
			stepWalker(walker, root.Position, camera)
		else
			walker.last = nil
		end
	end
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local now = os.clock()
	local eye = camera.CFrame.Position
	local inLevel = State.inLevel()
	refreshFilter()

	local closest = math.huge
	for model, walker in monsters do
		if model.Parent == nil then
			monsters[model] = nil
			continue
		end
		local disguised = CollectionService:HasTag(model, Config.Tags.disguised)
		if not inLevel or disguised then
			walker.last = nil
			continue
		end
		local distance = (walker.root.Position - eye).Magnitude
		closest = math.min(closest, distance)
		stepWalker(walker, walker.root.Position, eye)
		if distance <= tracks.mistRange then
			breathe(walker, now)
		end
	end

	updateMates(eye, inLevel or State.server.stage == "lore" or State.server.stage == "passage")

	local target = 0
	if inLevel then
		target = math.clamp(1 - closest / tracks.auraRange, 0, 1) ^ AURA_CURVE
	end
	aura += (target - aura) * math.min(1, dt * AURA_BLEND)
	Hud.setAura(aura)
end

function Presence.start()
	for _, model in CollectionService:GetTagged(Config.Tags.enemy) do
		task.spawn(watchMonster, model)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.enemy):Connect(function(model)
		task.spawn(watchMonster, model)
	end)
	Players.PlayerRemoving:Connect(function(leaving: Player)
		mates[leaving] = nil
		local marker = markers[leaving]
		if marker then
			marker.gui:Destroy()
			markers[leaving] = nil
		end
	end)
	State.onLevel(function()
		for _, walker in monsters do
			walker.last = nil
		end
		for _, walker in mates do
			walker.last = nil
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return Presence
