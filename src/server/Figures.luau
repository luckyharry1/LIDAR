--!strict
-- Humanoid and creature shapes built from primitives. They are never drawn: a figure exists
-- only as something for LIDAR rays to land on, so each one has a distinct outline in dots and
-- no silhouette at all when nobody is scanning it. Every figure is a Model whose PrimaryPart
-- sits on the floor at its centre.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Lore = require(ReplicatedStorage.Shared.data.Lore)

local Figures = {}

type Piece = {
	size: Vector3,
	offset: CFrame,
	shape: Enum.PartType?,
	color: Color3?, -- only a surveyor's pieces have colours: they are shown once found
}

local SKIN = Color3.fromRGB(214, 176, 142)
local FIGURE_MATERIAL = Enum.Material.Fabric

local function assemble(name: string, pieces: { Piece }, parent: Instance, tag: string?): Model
	local model = Build.model(name, parent)
	local root = Build.part({
		name = "Root",
		size = Vector3.new(1, 0.2, 1),
		cframe = CFrame.new(),
		transparency = 1,
		collide = false,
		query = false,
		parent = model,
	})
	for index, piece in pieces do
		Build.part({
			name = "Piece" .. index,
			size = piece.size,
			cframe = piece.offset,
			shape = piece.shape,
			color = piece.color,
			material = if piece.color then FIGURE_MATERIAL else nil,
			collide = false,
			transparency = 1,
			parent = model,
		})
	end
	Build.weldTo(root, model)
	if tag then
		CollectionService:AddTag(model, tag)
	end
	return model
end

local function sittingPieces(): { Piece }
	return {
		{
			size = Vector3.new(1.8, 2.2, 1),
			offset = CFrame.new(0, 1.5, 0.6) * CFrame.Angles(math.rad(12), 0, 0),
		},
		{
			size = Vector3.new(1.2, 1.2, 1.2),
			offset = CFrame.new(0, 3.1, 0.5),
			shape = Enum.PartType.Ball,
		},
		{
			size = Vector3.new(0.7, 0.7, 1.9),
			offset = CFrame.new(-0.5, 1.0, -0.6) * CFrame.Angles(math.rad(-35), 0, 0),
		},
		{
			size = Vector3.new(0.7, 0.7, 1.9),
			offset = CFrame.new(0.5, 1.0, -0.6) * CFrame.Angles(math.rad(-35), 0, 0),
		},
		{ size = Vector3.new(0.6, 1.6, 0.6), offset = CFrame.new(-0.5, 0.8, -1.5) },
		{ size = Vector3.new(0.6, 1.6, 0.6), offset = CFrame.new(0.5, 0.8, -1.5) },
		{
			size = Vector3.new(0.5, 1.8, 0.5),
			offset = CFrame.new(-1.15, 1.5, 0.1) * CFrame.Angles(math.rad(-40), 0, 0),
		},
		{
			size = Vector3.new(0.5, 1.8, 0.5),
			offset = CFrame.new(1.15, 1.5, 0.1) * CFrame.Angles(math.rad(-40), 0, 0),
		},
	}
end

-- A person sat on the floor with their knees up: rescuable surveyors, and Mimics.
function Figures.sitting(parent: Instance, tag: string?): Model
	return assemble("Sitting", sittingPieces(), parent, tag)
end

-- Tall and thin, arms hanging: a surveyor still walking a route.
function Figures.wanderer(parent: Instance, tag: string?): Model
	return assemble("Wanderer", {
		{ size = Vector3.new(0.7, 3.2, 0.7), offset = CFrame.new(-0.45, 1.6, 0) },
		{ size = Vector3.new(0.7, 3.2, 0.7), offset = CFrame.new(0.45, 1.6, 0) },
		{
			size = Vector3.new(1.7, 2.6, 0.9),
			offset = CFrame.new(0, 4.5, -0.15) * CFrame.Angles(math.rad(-8), 0, 0),
		},
		{
			size = Vector3.new(1.1, 1.1, 1.1),
			offset = CFrame.new(0, 6.4, -0.45),
			shape = Enum.PartType.Ball,
		},
		{ size = Vector3.new(0.5, 3.4, 0.5), offset = CFrame.new(-1.15, 3.9, -0.1) },
		{ size = Vector3.new(0.5, 3.4, 0.5), offset = CFrame.new(1.15, 3.9, -0.1) },
	}, parent, tag)
end

-- Low and wide with two great discs for ears: a switchboard operator that only listens.
function Figures.listener(parent: Instance, tag: string?): Model
	return assemble("Listener", {
		{ size = Vector3.new(2.4, 1.5, 4.2), offset = CFrame.new(0, 2.1, 0) },
		{
			size = Vector3.new(1.3, 1.3, 1.3),
			offset = CFrame.new(0, 2.7, -2.5),
			shape = Enum.PartType.Ball,
		},
		{
			size = Vector3.new(0.3, 2.6, 2.6),
			offset = CFrame.new(-1.0, 3.0, -2.5),
			shape = Enum.PartType.Cylinder,
		},
		{
			size = Vector3.new(0.3, 2.6, 2.6),
			offset = CFrame.new(1.0, 3.0, -2.5),
			shape = Enum.PartType.Cylinder,
		},
		{ size = Vector3.new(0.5, 1.7, 0.5), offset = CFrame.new(-1.3, 0.85, -1.6) },
		{ size = Vector3.new(0.5, 1.7, 0.5), offset = CFrame.new(1.3, 0.85, -1.6) },
		{ size = Vector3.new(0.5, 1.7, 0.5), offset = CFrame.new(-1.3, 0.85, 1.6) },
		{ size = Vector3.new(0.5, 1.7, 0.5), offset = CFrame.new(1.3, 0.85, 1.6) },
	}, parent, tag)
end

-- Far too tall, arms spread and reaching the floor: something with no fixed position.
function Figures.stalker(parent: Instance, tag: string?): Model
	return assemble("Stalker", {
		{ size = Vector3.new(0.6, 4.6, 0.6), offset = CFrame.new(-0.4, 2.3, 0) },
		{ size = Vector3.new(0.6, 4.6, 0.6), offset = CFrame.new(0.4, 2.3, 0) },
		{ size = Vector3.new(1.3, 3.4, 0.8), offset = CFrame.new(0, 6.3, 0) },
		{
			size = Vector3.new(0.9, 0.9, 0.9),
			offset = CFrame.new(0, 8.6, 0),
			shape = Enum.PartType.Ball,
		},
		{
			size = Vector3.new(0.4, 7.2, 0.4),
			offset = CFrame.new(-1.9, 4.6, 0) * CFrame.Angles(0, 0, math.rad(-14)),
		},
		{
			size = Vector3.new(0.4, 7.2, 0.4),
			offset = CFrame.new(1.9, 4.6, 0) * CFrame.Angles(0, 0, math.rad(14)),
		},
	}, parent, tag)
end

-- A person on their feet, about as tall as a player.
local function standingPieces(): { Piece }
	return {
		{ size = Vector3.new(0.7, 2.4, 0.7), offset = CFrame.new(-0.4, 1.2, 0) },
		{ size = Vector3.new(0.7, 2.4, 0.7), offset = CFrame.new(0.4, 1.2, 0) },
		{ size = Vector3.new(1.8, 2.2, 0.9), offset = CFrame.new(0, 3.5, 0) },
		{
			size = Vector3.new(1.1, 1.1, 1.1),
			offset = CFrame.new(0, 5.1, 0),
			shape = Enum.PartType.Ball,
		},
		{ size = Vector3.new(0.5, 2.1, 0.5), offset = CFrame.new(-1.15, 3.4, 0) },
		{ size = Vector3.new(0.5, 2.1, 0.5), offset = CFrame.new(1.15, 3.4, 0) },
	}
end

-- What each surveyor carries. Each is its own outline in dots, so a regular can tell them apart
-- before they speak. Offsets are in the figure's frame; the head sits at (0, 3.1, 0.5) when
-- seated and (0, 5.1, 0) standing.
local function gearPieces(gear: string, sits: boolean, coat: Color3): { Piece }
	local head = if sits then Vector3.new(0, 3.1, 0.5) else Vector3.new(0, 5.1, 0)
	local dark = coat:Lerp(Color3.new(0, 0, 0), 0.45)
	if gear == "cap" then
		return {
			{
				size = Vector3.new(1.3, 0.4, 1.3),
				offset = CFrame.new(head + Vector3.new(0, 0.55, 0)),
				color = dark,
			},
			{
				size = Vector3.new(1.1, 0.12, 0.7),
				offset = CFrame.new(head + Vector3.new(0, 0.4, -0.85)),
				color = dark,
			},
			{ size = Vector3.new(2, 0.4, 1.1), offset = CFrame.new(0, 2.45, 0), color = dark },
			{
				size = Vector3.new(0.6, 0.9, 0.6),
				offset = CFrame.new(1.35, 2.2, 0),
				color = coat:Lerp(Color3.new(1, 1, 1), 0.3),
			},
		}
	elseif gear == "ponytail" then
		return {
			{
				size = Vector3.new(0.4, 1.3, 0.4),
				offset = CFrame.new(head + Vector3.new(0, -0.4, 0.75)),
				color = dark,
			},
			{
				size = Vector3.new(1.4, 0.2, 1.4),
				offset = CFrame.new(head + Vector3.new(0, 0.5, 0.05)),
				color = dark,
				shape = Enum.PartType.Cylinder,
			},
			{
				size = Vector3.new(0.5, 0.5, 2.6),
				offset = CFrame.new(0, 1.7, -0.9),
				color = coat:Lerp(Color3.new(1, 1, 1), 0.6),
				shape = Enum.PartType.Cylinder,
			},
		}
	elseif gear == "headphones" then
		return {
			{
				size = Vector3.new(0.35, 0.95, 0.95),
				offset = CFrame.new(head + Vector3.new(-0.7, 0, 0)),
				color = dark,
				shape = Enum.PartType.Cylinder,
			},
			{
				size = Vector3.new(0.35, 0.95, 0.95),
				offset = CFrame.new(head + Vector3.new(0.7, 0, 0)),
				color = dark,
				shape = Enum.PartType.Cylinder,
			},
			{
				size = Vector3.new(1.5, 0.2, 0.3),
				offset = CFrame.new(head + Vector3.new(0, 0.65, 0)),
				color = dark,
			},
			{ size = Vector3.new(1.2, 0.8, 0.9), offset = CFrame.new(0, 1.9, -0.8), color = dark },
			{
				size = Vector3.new(0.12, 1.8, 0.12),
				offset = CFrame.new(0.4, 3, -0.8),
				color = dark,
			},
		}
	elseif gear == "lantern" then
		return {
			{ size = Vector3.new(1.4, 1.9, 0.7), offset = CFrame.new(0, 3.7, 0.8), color = dark },
			{
				size = Vector3.new(0.7, 0.9, 0.7),
				offset = CFrame.new(1.3, 1.6, -0.2),
				color = coat:Lerp(Color3.new(1, 0.9, 0.5), 0.7),
			},
			{
				size = Vector3.new(1, 0.45, 1),
				offset = CFrame.new(head + Vector3.new(0, 0.6, 0)),
				color = dark,
			},
		}
	else -- "scarf"
		return {
			{
				size = Vector3.new(1.5, 0.5, 1.2),
				offset = CFrame.new(0, 4.45, 0),
				color = coat:Lerp(Color3.new(1, 1, 1), 0.35),
			},
			{
				size = Vector3.new(0.45, 1.6, 0.25),
				offset = CFrame.new(0.5, 3.7, -0.55),
				color = coat:Lerp(Color3.new(1, 1, 1), 0.35),
			},
			{
				size = Vector3.new(0.25, 7, 0.25),
				offset = CFrame.new(1.8, 3.5, -0.4),
				color = dark,
			},
		}
	end
end

-- A surveyor from Lore.surveyors, built to be met. It is never drawn until it wakes: the
-- pieces start invisible (like every figure) and the client fades them in once the surveyor
-- is found, lit by a lamp of the surveyor's own colour. `tag` is Config.Tags.friend so a scan
-- shows green dots.
function Figures.surveyor(
	parent: Instance,
	who: Lore.Surveyor,
	tag: string?,
	sitting: boolean? -- overrides how they are posed (Pim stands in camp and sits in the maze)
): Model
	local sits = if sitting ~= nil then sitting else who.sits
	local coat = Color3.fromRGB(who.coat[1], who.coat[2], who.coat[3])
	local pieces: { Piece } = if sits then sittingPieces() else standingPieces()
	-- Body and limbs wear the coat, the head is skin.
	for _, piece in pieces do
		piece.color = if piece.shape == Enum.PartType.Ball then SKIN else coat
	end
	for _, piece in gearPieces(who.gear, sits, coat) do
		table.insert(pieces, piece)
	end
	return assemble(who.name, pieces, parent, tag)
end

return Figures
