--!strict
-- Nobody can see the cutscene pictures from the cloud, so this checks them with maths: every
-- camera of every shot of every set, against the blocks the set is made of. A camera that sits
-- on the floor (the bug that made every tape "empty") or inside a wall, a subject that is
-- behind the lens or cut off by the edge of the frame or hidden behind a block, a speaker too
-- small on the screen: each fails here.
local StageData = require("../src/shared/pure/StageData")

type Vec = StageData.Vec
type Block = StageData.Block
type Room = StageData.Room
type Seg = StageData.Seg
type Cue = StageData.Cue

local tests: { [string]: () -> () } = {}

local ASPECTS = { 4 / 3, 16 / 9 }
local CAMERA_MARGIN = 0.5
local MAX_DISTANCE = 45
local MAX_HOLD = 6
local MAX_PARTS = 700
local SAMPLES = { 0, 0.25, 0.5, 0.75, 1 }
local TAPE_IDS = {
	"tape.orientation",
	"tape.halden",
	"tape.hollis",
	"tape.tobi",
	"tape.ravi",
	"tape.quill",
	"tape.pike",
}

local function sortedRooms(): { Room }
	local list: { Room } = {}
	for _, room in StageData.rooms do
		table.insert(list, room)
	end
	table.sort(list, function(a: Room, b: Room): boolean
		return a.id < b.id
	end)
	return list
end

local function sortedCues(room: Room): { string }
	local names = {}
	for name in room.cues do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function isTape(room: Room): boolean
	return string.sub(room.id, 1, 5) == "tape."
end

local function solids(room: Room): { Block }
	local list = {}
	for _, block in room.blocks do
		if StageData.isSolid(block) then
			table.insert(list, block)
		end
	end
	return list
end

-- Calls `visit` for every sample of every segment of a cue.
local function eachSample(
	cue: Cue,
	visit: (seg: Seg, position: Vec, lookAt: Vec, e: number, t: number) -> ()
)
	local segs = cue.segs
	if segs == nil then
		return
	end
	for index, seg in segs do
		for _, share in SAMPLES do
			local before = 0
			for earlier = 1, index - 1 do
				before += segs[earlier].seconds
			end
			local t = before + seg.seconds * share
			local position, lookAt, _roll, found, e = StageData.cameraAt(segs, t)
			-- on a boundary the sample belongs to the earlier segment: use this one's own maths
			if found ~= index then
				position = StageData.lerp(
					seg.from,
					seg.toFrom or seg.from,
					StageData.ease(seg.ease, share)
				)
				lookAt = StageData.lerp(seg.at, seg.toAt or seg.at, StageData.ease(seg.ease, share))
				e = StageData.ease(seg.ease, share)
			end
			visit(seg, position, lookAt, e, t)
		end
	end
end

local function subjectAt(subject: StageData.Subject, e: number): Vec
	return StageData.lerp(subject[1], subject[2] or subject[1], e)
end

local function describe(room: Room, cueName: string, t: number): string
	return `{room.id}/{cueName} at {string.format("%.2f", t)}s`
end

local function assertFramed(
	label: string,
	room: Room,
	position: Vec,
	lookAt: Vec,
	point: Vec,
	letterboxed: boolean
)
	for _, aspect in ASPECTS do
		local x, y, depth = StageData.project(position, lookAt, room.fov, aspect, point)
		assert(depth > 0.5, `{label}: a subject is behind the lens`)
		assert(
			math.abs(x) <= 0.9,
			`{label}: a subject is cut off sideways ({string.format("%.2f", x)} at aspect {string.format(
				"%.2f",
				aspect
			)})`
		)
		local low, high = if letterboxed then -0.5 else -0.9, if letterboxed then 0.72 else 0.9
		assert(
			y >= low and y <= high,
			`{label}: a subject is off the picture vertically ({string.format("%.2f", y)} at aspect {string.format(
				"%.2f",
				aspect
			)})`
		)
	end
end

tests["every room opens on a shot that exists"] = function()
	for _, room in sortedRooms() do
		local cue = room.cues[room.start]
		assert(cue ~= nil, room.id .. " has no opening cue " .. room.start)
		assert(cue.segs ~= nil and #cue.segs > 0, room.id .. " opens on no camera")
	end
end

tests["no camera is inside a block or against a face"] = function()
	for _, room in sortedRooms() do
		local blocks = solids(room)
		for _, name in sortedCues(room) do
			eachSample(room.cues[name], function(_seg, position, _lookAt, _e, t)
				for _, block in blocks do
					assert(
						not StageData.insideBlock(block, position, CAMERA_MARGIN),
						`{describe(room, name, t)}: the camera is inside or against {block.name}`
					)
				end
			end)
		end
	end
end

tests["the floor camera of the tapes would be caught"] = function()
	local room = StageData.rooms["tape.hollis"]
	local caught = false
	for _, block in solids(room) do
		if StageData.insideBlock(block, { 0, 0, 0 }, CAMERA_MARGIN) then
			caught = true
		end
	end
	assert(caught, "a camera at the origin is not flagged")
end

tests["every subject is in front of the lens and inside the frame"] = function()
	for _, room in sortedRooms() do
		for _, name in sortedCues(room) do
			eachSample(room.cues[name], function(seg, position, lookAt, e, t)
				for _, subject in seg.subjects or {} do
					assertFramed(
						describe(room, name, t),
						room,
						position,
						lookAt,
						subjectAt(subject, e),
						not isTape(room)
					)
				end
			end)
		end
	end
end

tests["extra subjects are inside the room's main shot"] = function()
	for _, room in sortedRooms() do
		local main = room.cues[room.start]
		for _, name in sortedCues(room) do
			local cue = room.cues[name]
			for _, subject in cue.subjects or {} do
				for _, share in { 0, 1 } do
					local position, lookAt = StageData.cameraAt(
						main.segs :: { Seg },
						share * StageData.duration(main.segs :: { Seg })
					)
					assertFramed(
						`{room.id}/{name} subject`,
						room,
						position,
						lookAt,
						subject[1],
						not isTape(room)
					)
				end
			end
		end
	end
end

tests["no block cuts the line from the camera to a subject"] = function()
	for _, room in sortedRooms() do
		local blocks = solids(room)
		for _, name in sortedCues(room) do
			eachSample(room.cues[name], function(seg, position, _lookAt, e, t)
				for _, subject in seg.subjects or {} do
					local point = subjectAt(subject, e)
					for _, block in blocks do
						assert(
							not StageData.segmentHits(block, position, point, 0.06),
							`{describe(room, name, t)}: {block.name} stands between the camera and a subject`
						)
					end
				end
			end)
		end
	end
end

tests["every camera is close enough to what it looks at"] = function()
	for _, room in sortedRooms() do
		for _, name in sortedCues(room) do
			eachSample(room.cues[name], function(seg, position, lookAt, e, t)
				assert(
					StageData.length(StageData.sub(lookAt, position)) <= MAX_DISTANCE,
					`{describe(room, name, t)}: looks at something over {MAX_DISTANCE} studs away`
				)
				for _, subject in seg.subjects or {} do
					local far = StageData.length(StageData.sub(subjectAt(subject, e), position))
					assert(
						far <= MAX_DISTANCE,
						`{describe(room, name, t)}: a subject is {string.format("%.0f", far)} studs away`
					)
				end
			end)
		end
	end
end

tests["a tape speaker fills most of the screen but not all of it"] = function()
	local checked = 0
	for _, room in sortedRooms() do
		for _, name in sortedCues(room) do
			local fill = room.cues[name].fill
			if fill then
				eachSample(room.cues[name], function(_seg, position, lookAt, _e, t)
					local _x, _y, depth = StageData.project(
						position,
						lookAt,
						room.fov,
						4 / 3,
						{ fill.x, 4.5, fill.z }
					)
					local share = (fill.top - fill.bottom)
						/ (2 * depth * math.tan(math.rad(room.fov) / 2))
					assert(
						share >= 0.5 and share <= 0.8,
						`{describe(room, name, t)}: the speaker fills {string.format(
							"%.0f",
							share * 100
						)}% of the height`
					)
					checked += 1
				end)
			end
		end
	end
	assert(checked >= 6, "no tape was measured")
end

tests["all seven tapes have a room, and an unknown set shows none"] = function()
	for _, id in TAPE_IDS do
		assert(StageData.rooms[id] ~= nil, id .. " has no room")
		assert(StageData.roomFor("tape", id) == id, id .. " does not open its own room")
	end
	assert(StageData.roomFor("office", "x") == "office")
	assert(StageData.roomFor("lamp", "x") == "lamp")
	assert(StageData.roomFor("garage", "x") == nil, "an unknown set must have no picture")
	assert(StageData.roomFor("", "x") == nil)
end

tests["holds are short and ordered cues point at real cues"] = function()
	for _, room in sortedRooms() do
		for _, name in sortedCues(room) do
			local cue = room.cues[name]
			assert((cue.hold or 0) <= MAX_HOLD, `{room.id}/{name}: a hold over {MAX_HOLD}s`)
			if cue.after then
				local other = room.cues[cue.after[1] :: string]
				assert(other ~= nil, `{room.id}/{name}: waits for a cue that is not there`)
				assert(
					(cue.after[2] :: number) <= StageData.duration(other.segs :: { Seg }) + 0.001,
					`{room.id}/{name}: waits longer than the cue it follows lasts`
				)
			end
		end
	end
end

tests["a set stays under the part budget"] = function()
	for _, room in sortedRooms() do
		local parts = #room.blocks + 12 -- figures
		if room.scan then
			parts += room.scan.count
		end
		if room.id == "lamp" then
			parts += 370 -- the chalkboard's dots
		end
		assert(parts <= MAX_PARTS, `{room.id} would build {parts} parts`)
	end
end

tests["scanner dots land on real surfaces, in order"] = function()
	local scanned = 0
	for _, room in sortedRooms() do
		local scan = room.scan
		if scan then
			local dots = StageData.scanDots(room.blocks, scan)
			assert(#dots >= scan.count * 0.9, `{room.id}: only {#dots} of {scan.count} dots landed`)
			local last = -1
			for _, dot in dots do
				assert(dot.t >= last, room.id .. ": dots are not in sweep order")
				assert(dot.t >= 0 and dot.t <= 1, room.id .. ": a dot has no time")
				last = dot.t
				local onSurface = false
				for _, block in room.blocks do
					if not block.decor and block.rot == nil then
						if StageData.insideBlock(block, { dot.x, dot.y, dot.z }, 0.06) then
							onSurface = true
							break
						end
					end
				end
				assert(onSurface, `{room.id}: a dot floats at {dot.x}, {dot.y}, {dot.z}`)
			end
			scanned += 1
		end
	end
	assert(scanned == 3, "the office, the morning office and the wake-up room all scan")
end

tests["the scan is the same every time"] = function()
	local room = StageData.rooms.office
	local a = StageData.scanDots(room.blocks, room.scan :: StageData.Scan)
	local b = StageData.scanDots(room.blocks, room.scan :: StageData.Scan)
	assert(#a == #b and a[10].x == b[10].x and a[#a].z == b[#b].z)
end

tests["the wake-up room draws its doorway in gold dots"] = function()
	local room = StageData.rooms.wake
	local dots = StageData.scanDots(room.blocks, room.scan :: StageData.Scan)
	local gold, white = 0, 0
	for _, dot in dots do
		if dot.kind == "objective" then
			gold += 1
		else
			white += 1
		end
	end
	assert(gold >= 12, "the doorway is not drawn")
	assert(white > gold * 3, "the room is mostly bare walls")
end

tests["the scan of the office stays in front of the scanner"] = function()
	local room = StageData.rooms.office
	for _, dot in StageData.scanDots(room.blocks, room.scan :: StageData.Scan) do
		assert(dot.z < -6.9, "a dot landed behind the scanner")
	end
end

tests["the chalkboard keeps its gap dark"] = function()
	local filled, gap = StageData.boardDots(300, 70, 5)
	assert(#filled >= 280 and #gap >= 60, "the board did not fill")
	local board = StageData.board
	for _, dot in filled do
		assert(math.abs(dot.x) <= board.width / 2 and math.abs(dot.y) <= board.height / 2)
		for _, rect in board.gap do
			local inside = dot.x >= rect[1]
				and dot.x <= rect[3]
				and dot.y >= rect[2]
				and dot.y <= rect[4]
			assert(not inside, "a white dot landed in the gap")
		end
	end
	for _, dot in gap do
		local inside = false
		for _, rect in board.gap do
			if dot.x >= rect[1] and dot.x <= rect[3] and dot.y >= rect[2] and dot.y <= rect[4] then
				inside = true
			end
		end
		assert(inside, "a gold dot landed outside the gap")
	end
end

tests["everyone who speaks has a coat and a face worth looking at"] = function()
	for name in StageData.coats do
		assert(StageData.features[name] ~= nil, name .. " has no features entry")
	end
	for _, name in
		{ "Theo", "Ines", "Hollis", "Tobi", "Ravi", "Quill", "Pike", "Joss", "Hana", "Lena", "Pim" }
	do
		assert(#StageData.features[name] > 0, name .. " looks like nobody")
	end
	for name, list in StageData.features do
		for _, part in list do
			assert(
				part.size[1] > 0 and part.size[2] > 0 and part.size[3] > 0,
				name .. ": empty part"
			)
			assert(part.to == "head" or part.to == "torso", name .. ": rides on nothing")
		end
	end
end

tests["the camera maths agree with a known view"] = function()
	local x, y, depth = StageData.project({ 0, 0, 0 }, { 0, 0, -1 }, 90, 1, { 0, 0, -10 })
	assert(math.abs(x) < 1e-9 and math.abs(y) < 1e-9 and math.abs(depth - 10) < 1e-9)
	x, y = StageData.project({ 0, 0, 0 }, { 0, 0, -1 }, 90, 1, { 10, 10, -10 })
	assert(
		math.abs(x - 1) < 1e-9 and math.abs(y - 1) < 1e-9,
		"a point on the corner of a 90 degree view"
	)
	local _, _, behind = StageData.project({ 0, 0, 0 }, { 0, 0, -1 }, 60, 1.5, { 0, 0, 5 })
	assert(behind < 0)
end

return tests
