--!strict
-- Deterministic Lehmer PRNG. Pure arithmetic so every machine agrees on a seed.

local MODULUS = 2147483647
local MULTIPLIER = 48271

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number): Rng
	local state = math.floor(math.abs(seed)) % MODULUS
	if state == 0 then
		state = 1
	end
	return setmetatable({ state = state }, Rng)
end

-- Float in [0, 1).
function Rng.next(self: Rng): number
	self.state = (self.state * MULTIPLIER) % MODULUS
	return (self.state - 1) / (MODULUS - 1)
end

-- Integer in [lo, hi] inclusive.
function Rng.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng.shuffle<T>(self: Rng, list: { T })
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

return Rng
