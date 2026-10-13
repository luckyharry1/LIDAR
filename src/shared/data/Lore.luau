--!strict
-- All written lore. Rooms reference notes by id; adding a note or a room is a data change.
-- The story bible is in docs/LORE.md.

export type Note = { title: string, body: string }
export type Room = {
	id: string,
	title: string, -- shown as a title card on entry
	subtitle: string,
	theme: string, -- which furniture set the builder uses
	wall: { number }, -- RGB
	floor: { number },
	light: { number },
	notes: { string },
}

local Lore = {}

Lore.notes = {
	-- Office, after tier 2
	office_welcome = {
		title = "Pinned to the lamp",
		body = "If you are reading this by lamplight, somebody closed this room for you. A closed room stays lit and stays put. Rest here. Nothing from the unmeasured halls comes into a closed room.\n\nSay thank you. You will understand why later.\n\n- S.",
	},
	office_walkers = {
		title = "Field memo 12",
		body = "Staff who stay out past their sheet do not come back in. They keep walking their traverse lines, counting paces. They are slow and they follow noise. Do not call to them. Do not scan them twice. Walk the other way and let them lose count.",
	},
	office_timesheet = {
		title = "Timesheet, Annex contract",
		body = "Seven surveyors signed in on Monday. Seven lines, seven names, one hand. The loops on the letters are identical all the way down the page.\n\nSomeone has written in the margin: whose writing is this?",
	},
	-- Break room, after tier 5
	break_switchboard = {
		title = "Notice from the switchboard",
		body = "The operators took every field call this office ever received. They stayed at the board after the lights went. They cannot see you. They hear running. They hear a scanner held open too long.\n\nIf one is close: stop, stand to the side, and let it pass.",
	},
	break_drafts = {
		title = "Scrawled on a napkin",
		body = "The building has started drawing people. It draws what it has seen the most, and that is one of us sat waiting to be found.\n\nOurs tap on the wall so you can find them. A draft is silent, and your dots land on it a moment late. If it is quiet, leave it.",
	},
	break_rota = {
		title = "Kettle rota",
		body = "Mon: S.\nTue: S.\nWed: S.\nThu: S.\nFri: S.\n\nUnderneath, in the same hand: I have never met any of the others. Have you?",
	},
	-- Nursery, after tier 7
	nursery_log = {
		title = "Growth log",
		body = "Day 1. Seeds in. Day 40. First leaves. Day 200. Repotted. Day 412. Still no window, still growing.\n\nI keep the trays so I can prove that time passes in here. The rooms do not change. The plants do. So do I.",
	},
	nursery_unmeasured = {
		title = "Taped to the grow lamp",
		body = "The tall ones have no position until an instrument gives them one. Point the scanner and they are somewhere, and they stay there. Look away and they are wherever they like.\n\nHold one in the cone for a few breaths and it loses its nerve and goes back where it came from. Look away first and you have chosen where it is. It will be behind you.",
	},
	nursery_growth = {
		title = "Survey principle, crossed out twice",
		body = "We were told the Annex had rooms we had not measured yet. That is backwards. It has rooms because we measure. Every sheet we close, it builds two more to stay ahead of us.\n\nThe plants grow where I leave them alone. The building grows where I look.",
	},
	-- Stairwell and the Datum, after tier 8
	stair_passlog = {
		title = "Pass log",
		body = "Pass 1. Reached Records. Pass 9. Reached the Switchboard. Pass 31. Closed the Drafting Hall. Pass 58. Found the stairs.\n\nThe gun keeps every scan from every pass. It never forgot the way down. I did, each time.",
	},
	stair_datum = {
		title = "Brass plate on the desk",
		body = "DATUM. The zero point. Every distance in the Annex is measured from this room.\n\nThis is the office where you were handed the scanner. It was the first room ever closed. The Annex was not a job the office took on. It is what grew out of the office the day someone measured it.",
	},
	stair_final = {
		title = "The last sheet, in your handwriting",
		body = "There were never seven surveyors. There was one, sent down seven times and seven hundred. S. was only ever short for Surveyor.\n\nYou cannot finish a building that grows when it is measured. You can close rooms, and you can leave the lamps on for the next pass.\n\nThank you for the lights. Now write the next note.",
	},
	-- Rest landing, between endless tiers
	landing_1 = {
		title = "Note for the next pass",
		body = "You made it past the Datum. Nobody has drawn these halls before, not even us. Close what you can. Leave a lamp on.",
	},
	landing_2 = {
		title = "Note for the next pass",
		body = "The Static on your sheet is whatever the scanner picked up that was not a wall. Spend it at the bench. It is no use to the dark.",
	},
	landing_3 = {
		title = "Note for the next pass",
		body = "If you find one of ours tapping on a wall, bring them in. Every pass that walks out makes the next one shorter.",
	},
} :: { [string]: Note }

Lore.rooms = {
	office = {
		id = "office",
		title = "Survey Office",
		subtitle = "Closed room. You are safe here.",
		theme = "office",
		wall = { 196, 178, 150 },
		floor = { 120, 86, 60 },
		light = { 255, 214, 170 },
		notes = { "office_welcome", "office_walkers", "office_timesheet" },
	},
	breakroom = {
		id = "breakroom",
		title = "Break Room",
		subtitle = "Closed room. The kettle is still warm.",
		theme = "breakroom",
		wall = { 178, 190, 170 },
		floor = { 150, 140, 120 },
		light = { 255, 224, 190 },
		notes = { "break_switchboard", "break_drafts", "break_rota" },
	},
	nursery = {
		id = "nursery",
		title = "Nursery",
		subtitle = "Closed room. Something green, at last.",
		theme = "nursery",
		wall = { 205, 196, 170 },
		floor = { 110, 100, 84 },
		light = { 255, 200, 220 },
		notes = { "nursery_log", "nursery_unmeasured", "nursery_growth" },
	},
	stairwell = {
		id = "stairwell",
		title = "The Datum",
		subtitle = "The first room ever closed.",
		theme = "stairwell",
		wall = { 186, 176, 160 },
		floor = { 96, 90, 84 },
		light = { 255, 206, 150 },
		notes = { "stair_passlog", "stair_datum", "stair_final" },
	},
	landing = {
		id = "landing",
		title = "Landing",
		subtitle = "A lamp left on between passes.",
		theme = "landing",
		wall = { 190, 184, 172 },
		floor = { 104, 96, 88 },
		light = { 255, 218, 176 },
		notes = { "landing_1", "landing_2", "landing_3" },
	},
} :: { [string]: Room }

-- Rare survey plates found inside mazes: one per run at most.
Lore.plates = {
	"Plate 1. Measured rooms hold still.",
	"Plate 2. Count your paces out loud and you will hear someone counting with you.",
	"Plate 3. The dark is not empty. It is undrawn.",
	"Plate 4. Green means one of ours. Usually.",
	"Plate 5. A scanner held open is a voice.",
	"Plate 6. The exit is always the far end of what you have not seen.",
	"Plate 7. We do not map the Annex. We ask it where it is.",
	"Plate 8. Leave a lamp on.",
} :: { string }

-- Ending card shown once after the Datum.
Lore.ending = {
	title = "Pass closed",
	body = "You signed the last sheet and left the lamp on.\n\nThe Annex is already longer than it was this morning. The survey continues.",
}

return Lore
