--!strict
-- Humanoid and creature shapes built from primitives. They are never drawn: a figure exists
-- only as something for LIDAR rays to land on, so each one has a distinct outline in dots and
-- no silhouette at all when nobody is scanning it. Every figure is a Model whose PrimaryPart
-- sits on the floor at its centre.

local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Build)

local Figures = {}

type Piece = { size: Vector3, offset: CFrame, shape: Enum.PartType? }

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

-- A person sat on the floor with their knees up: rescuable surveyors, and Mimics.
function Figures.sitting(parent: Instance, tag: string?): Model
	return assemble("Sitting", {
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
	}, parent, tag)
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

return Figures
