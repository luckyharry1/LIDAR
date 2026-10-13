--!strict
-- Enemy definitions. Speeds and radii are in studs; EnemyBrain converts to maze cells.
-- For reference the player crouches at 5 studs/s, walks at 10 and sprints at 17.
-- Monsters roam the whole level, pausing briefly wherever they arrive.

export type EnemyDef = {
	displayName: string,
	rule: string, -- the learnable rule, shown when it catches you and in the field guide
	patrolSpeed: number, -- roaming
	alertSpeed: number, -- investigating or hunting
	chaseSpeed: number,
	hearing: number, -- multiplier on noise radius; 0 means deaf
	sightCells: number, -- sees an upright player along a clear line within this many cells; 0 means blind
	chaseCells: number, -- starts a chase when a sensed player is within this path distance
	loseCells: number, -- gives up the chase beyond this path distance
	searchSeconds: number,
	lingerMin: number, -- seconds it pauses after reaching a spot
	lingerMax: number,
	catchRadius: number,
	minSpawnCells: number, -- minimum path distance from the level start
}

local Enemies: { [string]: EnemyDef } = {
	wanderer = {
		displayName = "Wanderer",
		rule = "Slow. It sees you standing or walking in its line of sight and hears running. Crouch and it loses you.",
		patrolSpeed = 5,
		alertSpeed = 6.5,
		chaseSpeed = 8.8,
		hearing = 1,
		sightCells = 2.4,
		chaseCells = 2,
		loseCells = 3,
		searchSeconds = 3,
		lingerMin = 1.5,
		lingerMax = 4,
		catchRadius = 4,
		minSpawnCells = 4,
	},
	listener = {
		displayName = "Listener",
		rule = "Blind and fast. It hunts running, footsteps close by and the sweep. Crouch to move in silence.",
		patrolSpeed = 4.5,
		alertSpeed = 13,
		chaseSpeed = 13,
		hearing = 1.6,
		sightCells = 0,
		chaseCells = 0,
		loseCells = 0,
		searchSeconds = 3,
		lingerMin = 1,
		lingerMax = 3,
		catchRadius = 3.5,
		minSpawnCells = 5,
	},
	mimic = {
		displayName = "Mimic",
		rule = "It marks green until you are close. Its dots land late and it never taps on the wall.",
		patrolSpeed = 0,
		alertSpeed = 0,
		chaseSpeed = 14.5,
		hearing = 0,
		sightCells = 0,
		chaseCells = 0.95, -- reveal distance, in cells
		loseCells = 6,
		searchSeconds = 5, -- how long the chase lasts
		lingerMin = 0,
		lingerMax = 0,
		catchRadius = 4,
		minSpawnCells = 5,
	},
	stalker = {
		displayName = "Stalker",
		rule = "It only moves while no scanner points at it. Keep your dots on it and it withdraws.",
		patrolSpeed = 0,
		alertSpeed = 12,
		chaseSpeed = 12,
		hearing = 0,
		sightCells = 7, -- how far away a scan can pin it
		chaseCells = 4, -- wakes when a player is within this path distance
		loseCells = 7,
		searchSeconds = 0,
		lingerMin = 0,
		lingerMax = 0,
		catchRadius = 4,
		minSpawnCells = 6,
	},
}

return Enemies
