--!strict
-- Remote names shared by server and client. The server creates the instances
-- (see server/Remotes); clients fetch them with Net.get.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.folderName = "Remotes"

-- Client to server. Every one of these is validated and rate limited in server/Remotes.
Net.clientToServer = {
	-- (firing, sweeping, crouching: boolean, look: Vector3, origin: Vector3, spreadDeg: number)
	"ScanState", -- unreliable
	"Reveal", -- (echoId: number) this client has scanned a hidden recorder enough to reveal it
	"Ping", -- (position: Vector3)
	"Emote", -- (index: number)
	"BuyUpgrade", -- (upgradeId: string)
	"EquipCosmetic", -- (slot: string, cosmeticId: string)
	"ToggleUpgrade", -- (upgradeId: string, on: boolean)
	"SetSetting", -- (key: string, value: any)
	"Start", -- (mode: "continue" | "new" | "daily")
	"Funnel", -- (step: string) onboarding steps only the client can observe
	"Choose", -- (choice: "up" | "stay") the finale: climb the ladder or keep the lamp
	"Descend", -- (yes: boolean) the answer to a doorway's "go down?" pop-up
	"PartyReady", -- (on: boolean) Play Together: ready to go in with the others on this server
	"PartyStart", -- (mode: "continue" | "new" | "daily") go in now, with everyone who is ready
}

-- Server to client.
Net.serverToClient = {
	"State", -- (state table) where the player is and what the level is
	"Profile", -- (profile table, effects table)
	"Toast", -- (text: string, kind: string?)
	"Caught", -- (enemyKind: string, downed: boolean)
	"Revived", -- ()
	"LevelCleared", -- (summary table)
	"ScanRelay", -- (userId, firing, sweeping, look, origin, spreadDeg) unreliable
	"PingMarker", -- (userId: number, position: Vector3, lifetime: number)
	"EmoteShown", -- (userId: number, index: number)
	"OpenBench", -- ()
	"OpenNote", -- (title: string, body: string)
	"AskDescend", -- (body: string) a doorway asks whether to go down the stairwell
	"Objective", -- (kind: string, detail table) pickups, rescues, key, exit
	"Echo", -- (echoId: number, position: Vector3, speaker: string, line: string) a recorder spoke
	"Hazard", -- (kind: "plate" | "pit", position: Vector3, userId: number)
	"DailyBoard", -- (board table)
	"Ending", -- (title: string, body: string)
}

Net.unreliable = { ScanState = true, ScanRelay = true }

function Net.get(name: string): RemoteEvent | UnreliableRemoteEvent
	local folder = ReplicatedStorage:WaitForChild(Net.folderName)
	return folder:WaitForChild(name) :: any
end

return Net
