--!strict
-- Remote names shared by server and client. The server creates the instances
-- (see server/Remotes); clients fetch them with Net.get.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.folderName = "Remotes"

-- Client to server. Every one of these is validated and rate limited in server/Remotes.
Net.clientToServer = {
	"ScanState", -- (firing: boolean, focusing: boolean, look: Vector3, origin: Vector3) unreliable
	"Ping", -- (position: Vector3)
	"Emote", -- (index: number)
	"BuyUpgrade", -- (upgradeId: string)
	"EquipCosmetic", -- (slot: string, cosmeticId: string)
	"ToggleUpgrade", -- (upgradeId: string, on: boolean)
	"SetSetting", -- (key: string, value: any)
	"Start", -- (mode: "continue" | "new" | "daily")
	"Funnel", -- (step: string) onboarding steps only the client can observe
}

-- Server to client.
Net.serverToClient = {
	"State", -- (state table) where the player is and what the level is
	"Profile", -- (profile table, effects table)
	"Toast", -- (text: string, kind: string?)
	"Caught", -- (enemyKind: string, downed: boolean)
	"Revived", -- ()
	"LevelCleared", -- (summary table)
	"ScanRelay", -- (userId, firing, focusing, look, origin) unreliable
	"PingMarker", -- (userId: number, position: Vector3, lifetime: number)
	"EmoteShown", -- (userId: number, index: number)
	"OpenBench", -- ()
	"OpenNote", -- (title: string, body: string)
	"Objective", -- (kind: string, detail table) pickups, rescues, key, exit
	"DailyBoard", -- (board table)
	"Ending", -- (title: string, body: string)
}

Net.unreliable = { ScanState = true, ScanRelay = true }

function Net.get(name: string): RemoteEvent | UnreliableRemoteEvent
	local folder = ReplicatedStorage:WaitForChild(Net.folderName)
	return folder:WaitForChild(name) :: any
end

return Net
