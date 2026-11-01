--!strict
-- Surveyors waiting in the camps. Until someone finds them they are only what the scanner
-- shows: a person-shaped cluster of green dots in the dark, knocking the greeting (two taps, a
-- breath, one) so a player can follow the sound. A few dots on them, or the room's lamp coming
-- on, wakes them: a lamp of their own colour fades up, they become visible, and they talk (the
-- scene in Lore.surveyors). Everything here is client side, so each player in a party meets
-- them for themselves.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Audio = require(script.Parent.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Cutscene = require(script.Parent.Cutscene)
local Lidar = require(script.Parent.Lidar)
local State = require(script.Parent.State)

local WAIT_FOR_FREE_SECONDS = 12 -- how long a scene waits for a tape or another scene to end
local CHEST_HEIGHT = 2.6 -- studs above the floor point a scan counts as "on them"

type Record = {
	model: Model,
	root: BasePart,
	room: string,
	hits: number,
	awake: boolean,
}

local Surveyors = {}

local records: { [Model]: Record } = {}
local met: { [string]: boolean } = {} -- scenes already played this session

local function playScene(record: Record)
	local scene = record.model:GetAttribute("Scene")
	if type(scene) ~= "string" or met[scene] then
		return
	end
	local waited = 0
	while Cutscene.playing and waited < WAIT_FOR_FREE_SECONDS do
		waited += task.wait(0.25)
	end
	-- They only speak while their camp is still the room you are in.
	if
		Cutscene.playing
		or record.model.Parent == nil
		or State.server.stage ~= "lore"
		or State.server.loreRoom ~= record.room
	then
		return
	end
	met[scene] = true
	Cutscene.play(scene)
end

-- The surveyor is found: a lamp wakes on them, the person fades in, the greeting ends.
local function wake(record: Record, delay: number)
	if record.awake then
		return
	end
	record.awake = true
	local model = record.model
	model:SetAttribute("Awake", true)
	local lampColor = model:GetAttribute("Lamp")
	local light = Instance.new("PointLight")
	light.Color = if typeof(lampColor) == "Color3" then lampColor else Color3.fromRGB(255, 220, 170)
	light.Range = Config.Surveyor.lightRange
	light.Brightness = 0
	light.Shadows = false
	light.Parent = record.root
	local fade = TweenInfo.new(Config.Surveyor.fadeSeconds, Enum.EasingStyle.Sine)
	TweenService:Create(light, fade, { Brightness = Config.Surveyor.lightBrightness }):Play()
	for _, piece in model:GetChildren() do
		if piece:IsA("BasePart") and piece ~= record.root then
			TweenService:Create(piece, fade, { Transparency = 0 }):Play()
		end
	end
	Audio.echo(record.root.Position)
	task.delay(delay, playScene, record)
end

local function track(model: Instance)
	if not model:IsA("Model") or records[model] ~= nil then
		return
	end
	local root = model:WaitForChild("Root", 5)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local room = if model.Parent then string.gsub(model.Parent.Name, "^LoreRoom_", "") else ""
	local record: Record = { model = model, root = root, room = room, hits = 0, awake = false }
	records[model] = record
	model.Destroying:Connect(function()
		records[model] = nil
	end)
	-- The room's lamp coming on is the other way to find them.
	local zone = if model.Parent then model.Parent:FindFirstChild("LitZone") else nil
	if zone ~= nil then
		local function check()
			if zone:GetAttribute("Revealed") == true then
				wake(record, Config.Surveyor.roomLitDelay)
			end
		end
		zone:GetAttributeChangedSignal("Revealed"):Connect(check)
		check()
	end
end

function Surveyors.start()
	Lidar.onHit(function(position: Vector3)
		for _, record in records do
			if record.awake then
				continue
			end
			local chest = record.root.Position + Vector3.new(0, CHEST_HEIGHT, 0)
			if (chest - position).Magnitude <= Config.Surveyor.wakeReach then
				record.hits += 1
				if record.hits >= Config.Surveyor.wakeHits then
					wake(record, Config.Surveyor.sceneDelay)
				end
			end
		end
	end)
	for _, model in CollectionService:GetTagged(Config.Tags.surveyor) do
		task.spawn(track, model)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.surveyor):Connect(function(model)
		task.spawn(track, model)
	end)
end

return Surveyors
