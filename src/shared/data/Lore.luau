--!strict
-- All written story. Rooms reference notes by id; adding a note, a room or a recorder line is
-- a data change. The story bible is in docs/LORE.md.

export type Note = { title: string, body: string }
export type Room = {
	id: string,
	title: string, -- shown as a title card on entry
	subtitle: string,
	theme: string, -- which layout the builder uses
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
		body = "Staff who stay out past their sheet do not come back in. They keep walking their traverse lines, counting paces. They are slow. They see you if you stand in front of them and they hear running.\n\nGet low and keep still and they walk straight past. They leave red where they step. Watch the floor.",
	},
	office_timesheet = {
		title = "Timesheet, Annex contract",
		body = "Seven surveyors signed in on Monday. Seven lines, seven names, one hand. The loops on the letters are identical all the way down the page.\n\nSomeone has written in the margin: whose writing is this?",
	},
	-- Cistern, after tier 4
	cistern_falls = {
		title = "Chalked on the railing",
		body = "The water comes down from somewhere above the Annex and it has always been lit in here. I did not close this room. Nobody did. It was like this when the first pass found it.\n\nNothing follows you in. Drink, sit, look at a colour that is not white dots.",
	},
	cistern_switchboard = {
		title = "Notice from the switchboard",
		body = "The operators took every field call this office ever received. They stayed at the board after the lights went. They cannot see you. They hear running, footsteps close by, and the big sweep.\n\nCrouch and you make no sound at all. Except in water. Do not wade near them.",
	},
	cistern_log = {
		title = "Growth log",
		body = "Day 1. Moss on the wet stones. Day 40. First ferns. Day 200. Moved three of them nearer the fall. Day 412. Still no sky, still growing.\n\nI keep the log so I can prove that time passes in here. The rooms do not change. The ferns do. So do I.",
	},
	-- Break room, after tier 6
	break_drafts = {
		title = "Scrawled on a napkin",
		body = "The building has started drawing people. It draws what it has seen the most, and that is one of us sat waiting to be found.\n\nOurs tap on the wall so you can find them. A draft is silent, and your dots land on it a moment late. If it is quiet, leave it.",
	},
	break_unmeasured = {
		title = "Taped to the kettle",
		body = "The tall ones have no position until an instrument gives them one. Put your dots on one and it is somewhere, and it stays there. Hold it a few breaths and it loses its nerve and goes back where it came from.\n\nLook away first and you have chosen where it is. It will be behind you.",
	},
	break_rota = {
		title = "Kettle rota",
		body = "Mon: S.\nTue: S.\nWed: S.\nThu: S.\nFri: S.\n\nUnderneath, in the same hand: I have never met any of the others. Have you?",
	},
	-- Stairwell and the Datum, after tier 8
	stair_passlog = {
		title = "Pass log",
		body = "Pass 1. Reached Records. Pass 9. Reached the Switchboard. Pass 31. Found the water. Pass 58. Found the stairs.\n\nThe scanner keeps every dot from every pass. It never forgot the way down. I did, each time.",
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
	cistern = {
		id = "cistern",
		title = "The Cistern",
		subtitle = "Falling water, and light. Nothing follows you in.",
		theme = "cistern",
		wall = { 96, 118, 124 },
		floor = { 84, 96, 92 },
		light = { 170, 230, 255 },
		notes = { "cistern_falls", "cistern_switchboard", "cistern_log" },
	},
	breakroom = {
		id = "breakroom",
		title = "Break Room",
		subtitle = "Closed room. The kettle is still warm.",
		theme = "breakroom",
		wall = { 178, 190, 170 },
		floor = { 150, 140, 120 },
		light = { 255, 224, 190 },
		notes = { "break_drafts", "break_unmeasured", "break_rota" },
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

-- Field recorders hidden in the maze. Scan one enough and it reveals itself, lights its
-- corner of the level and plays its line. Each player hears them in this order, so the story
-- unfolds the same way however the levels are explored.
Lore.echoSpeaker = "RECORDER"
Lore.echoes = {
	"Recorder check. Surveyor, pass one. The Annex is dark and I have a scanner. That is all I know.",
	"The dots stay. Whatever I mark is still marked when I come back. It remembers for me.",
	"Something walked through my dots today. It left red where it stepped. I stayed down and it went by.",
	"Found a lantern somebody left burning. Under it the floor is just a floor. I had forgotten floors were ordinary.",
	"Watch the ground. Some of it is not there. The dots fall a long way before they land.",
	"The ones that click cannot see. They come to noise. I crouched in the water and they still heard me.",
	"There is a room with a waterfall. It is lit, and nothing follows you in. I do not understand it and I do not want to.",
	"I helped a man up off the floor today and he pointed me to the exit. He had my boots on.",
	"One of the green ones did not tap on the wall. I walked up anyway. Do not walk up anyway.",
	"The tall thing only moves when my scanner is off it. I kept my dots on it and it backed away, as if I were the frightening one.",
	"I keep finding these recorders. I do not remember leaving them. The voice on them is mine.",
	"Every pass I map a little more and forget a little more. The scanner keeps what I lose.",
	"Datum is below. Everything is measured from there. I think that includes me.",
	"If you are hearing this, you are further than I got on this pass. Leave a lamp on.",
} :: { string }

-- Rare survey plates found inside mazes: one per run at most.
Lore.plates = {
	"Plate 1. Measured rooms hold still.",
	"Plate 2. Count your paces out loud and you will hear someone counting with you.",
	"Plate 3. The dark is not empty. It is undrawn.",
	"Plate 4. Green means one of ours. Usually.",
	"Plate 5. The sweep is a voice. Everything hears it.",
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
