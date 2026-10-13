--!strict
-- Every tunable lives here.

local Config = {
	Lidar = {
		dotsPerSecond = 40,
		focusDotsPerSecond = 110,
		coneHalfAngleDeg = 12,
		focusConeHalfAngleDeg = 3,
		maxRange = 120,
		maxLiveDots = 3000,
		dotSize = 0.18,
		terrainLifetime = 8,
		friendLifetime = 6,
		enemyLifetime = 3,
		heatPerSecondFocus = 0.35,
		coolPerSecond = 0.2,
		overheatLockSeconds = 2,
	},
	Colors = {
		default = {
			terrain = Color3.fromRGB(255, 255, 255),
			friend = Color3.fromRGB(80, 255, 120),
			enemy = Color3.fromRGB(255, 50, 50),
		},
		colorblind = {
			terrain = Color3.fromRGB(255, 255, 255),
			friend = Color3.fromRGB(80, 160, 255),
			enemy = Color3.fromRGB(255, 150, 30),
		},
	},
	Tags = {
		terrain = "Lidar_Terrain",
		friend = "Lidar_Friend",
		enemy = "Lidar_Enemy",
	},
}

return Config
