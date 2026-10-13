--!strict
-- Builds the M1 test room: terrain, a friend dummy and an enemy dummy.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

Lighting.Brightness = 0
Lighting.Ambient = Color3.new(0, 0, 0)
Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
Lighting.ClockTime = 0
Lighting.FogEnd = 400
Lighting.FogColor = Color3.new(0, 0, 0)
Lighting.GlobalShadows = false

local room = Instance.new("Folder")
room.Name = "TestRoom"
room.Parent = workspace

local function part(name: string, size: Vector3, position: Vector3, tag: string?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Anchored = true
	p.Material = Enum.Material.Concrete
	p.Color = Color3.fromRGB(60, 60, 60)
	if tag then
		CollectionService:AddTag(p, tag)
	end
	p.Parent = room
	return p
end

part("Floor", Vector3.new(60, 1, 60), Vector3.new(0, 0, 0), nil)
part("WallN", Vector3.new(60, 14, 1), Vector3.new(0, 7, -30), nil)
part("WallS", Vector3.new(60, 14, 1), Vector3.new(0, 7, 30), nil)
part("WallE", Vector3.new(1, 14, 60), Vector3.new(30, 7, 0), nil)
part("WallW", Vector3.new(1, 14, 60), Vector3.new(-30, 7, 0), nil)
for i = 1, 4 do
	part("Pillar" .. i, Vector3.new(3, 14, 3), Vector3.new(-18 + i * 9, 7, -8), nil)
end

local friend =
	part("FriendDummy", Vector3.new(2, 5, 2), Vector3.new(-10, 3, 12), Config.Tags.friend)
friend.Shape = Enum.PartType.Cylinder
local enemy = part("EnemyDummy", Vector3.new(3, 6, 3), Vector3.new(12, 3.5, 10), Config.Tags.enemy)
enemy.Shape = Enum.PartType.Ball

local spawn = Instance.new("SpawnLocation")
spawn.Position = Vector3.new(0, 1.5, 24)
spawn.Anchored = true
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Parent = room
