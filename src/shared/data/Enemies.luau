--!strict
-- Enemy definitions. Speeds and radii are in studs; EnemyBrain converts to maze cells.
-- For reference the player walks at 10 studs/s and sprints at 17 (see Config.Player).

export type EnemyDef = {
	displayName: string,
	rule: string, -- the learnable rule, shown in the field guide once met
	patrolSpeed: number,
	alertSpeed: number, -- investigating or hunting
	chaseSpeed: number,
	hearing: number, -- multiplier on noise radius; 0 means deaf
	sightCells: number, -- sees a scanning player along a clear line within this many cells; 0 means blind
	chaseCells: number, -- starts a chase when a sensed player is within this path distance
	loseCells: number, -- gives up the chase beyond this path distance
	searchSeconds: number,
	catchRadius: number,
	minSpawnCells: number, -- minimum path distance from the level start
}

local Enemies: { [string]: EnemyDef } = {
	wanderer = {
		displayName = "Wanderer",
		rule = "Slow. Follows sound and nearby scanning. Go quiet and walk away and it loses you.",
		patrolSpeed = 4,
		alertSpeed = 6.5,
		chaseSpeed = 8.5,
		hearing = 1,
		sightCells = 3,
		chaseCells = 2,
		loseCells = 3,
		searchSeconds = 3,
		catchRadius = 4,
		minSpawnCells = 4,
	},
	listener = {
		displayName = "Listener",
		rule = "Blind and fast. Hunts noise: running and heavy scanning. Go quiet and step aside.",
		patrolSpeed = 2.5,
		alertSpeed = 13.5,
		chaseSpeed = 13.5,
		hearing = 1.8,
		sightCells = 0,
		chaseCells = 0,
		loseCells = 0,
		searchSeconds = 3.5,
		catchRadius = 3.5,
		minSpawnCells = 5,
	},
	mimic = {
		displayName = "Mimic",
		rule = "Reads green until you are close. Its dots land late and it never makes a sound.",
		patrolSpeed = 0,
		alertSpeed = 0,
		chaseSpeed = 14.5,
		hearing = 0,
		sightCells = 0,
		chaseCells = 0.95, -- reveal distance, in cells
		loseCells = 6,
		searchSeconds = 5, -- how long the chase lasts
		catchRadius = 4,
		minSpawnCells = 5,
	},
	stalker = {
		displayName = "Stalker",
		rule = "Only moves while no scanner points at it. Hold it in your cone and it withdraws. Focus is faster.",
		patrolSpeed = 0,
		alertSpeed = 12,
		chaseSpeed = 12,
		hearing = 0,
		sightCells = 7, -- how far away a scan can pin it
		chaseCells = 4, -- wakes when a player is within this path distance
		loseCells = 7,
		searchSeconds = 0,
		catchRadius = 4,
		minSpawnCells = 6,
	},
}

return Enemies
