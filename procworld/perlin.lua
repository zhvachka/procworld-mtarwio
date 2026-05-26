-- Ken Perlin improved noise 2D. perlin.create(seed) / :noise2d / :fractal2d / :ridge2d.
-- createPeriodic(seed, size) — тайлируемый вариант для текстур.

perlin = {}
perlin.__index = perlin

local function lcg(seed)
    local state = (tonumber(seed) or 0) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function()
        state = (state * 16807) % 2147483647
        return state
    end
end

local function shufflePerm(seed)
    local rng = lcg(seed)
    local perm = {}
    for i = 0, 255 do perm[i] = i end
    -- Fisher-Yates
    for i = 255, 1, -1 do
        local j = rng() % (i + 1)
        perm[i], perm[j] = perm[j], perm[i]
    end
    -- Удвоить, чтобы избежать модульной проверки в hot loop.
    for i = 0, 255 do perm[256 + i] = perm[i] end
    return perm
end

local function fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(t, a, b)
    return a + t * (b - a)
end

local function grad2d(hash, x, y)
    local h = hash % 8
    local u = h < 4 and x or y
    local v = h < 4 and y or x
    if h % 2 ~= 0 then u = -u end
    if math.floor(h / 2) % 2 ~= 0 then v = -v end
    return u + v
end

function perlin.create(seed)
    local self = setmetatable({}, perlin)
    self.perm = shufflePerm(seed)
    self.seed = seed
    self.period = 256
    return self
end

-- Periodic perlin для тайлируемых текстур. shuffleSize должен быть степенью двойки.
function perlin.createPeriodic(seed, shuffleSize)
    shuffleSize = shuffleSize or 32
    local self = setmetatable({}, perlin)
    local rng = lcg(seed)
    local perm = {}
    for i = 0, shuffleSize - 1 do perm[i] = i end
    for i = shuffleSize - 1, 1, -1 do
        local j = rng() % (i + 1)
        perm[i], perm[j] = perm[j], perm[i]
    end
    for i = 0, shuffleSize - 1 do perm[shuffleSize + i] = perm[i] end
    self.perm = perm
    self.seed = seed
    self.period = shuffleSize
    return self
end

function perlin:noise2d(x, y)
    local perm = self.perm
    local period = self.period or 256
    local xi = math.floor(x) % period
    local yi = math.floor(y) % period
    if xi < 0 then xi = xi + period end
    if yi < 0 then yi = yi + period end
    local xf = x - math.floor(x)
    local yf = y - math.floor(y)

    local u = fade(xf)
    local v = fade(yf)

    local xi1 = (xi + 1) % period
    local yi1 = (yi + 1) % period
    local a  = perm[xi]  + yi
    local b  = perm[xi1] + yi
    local a1 = perm[xi]  + yi1
    local b1 = perm[xi1] + yi1
    local aa = perm[a  % period]
    local ab = perm[a1 % period]
    local ba = perm[b  % period]
    local bb = perm[b1 % period]

    local x0 = lerp(u, grad2d(aa, xf, yf),     grad2d(ba, xf - 1, yf))
    local x1 = lerp(u, grad2d(ab, xf, yf - 1), grad2d(bb, xf - 1, yf - 1))
    return lerp(v, x0, x1)
end

function perlin:fractal2d(x, y, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0.5
    lacunarity = lacunarity or 2.0
    local sum = 0
    local amplitude = 1
    local frequency = 1
    local maxAmp = 0
    for _ = 1, octaves do
        sum = sum + self:noise2d(x * frequency, y * frequency) * amplitude
        maxAmp = maxAmp + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end
    if maxAmp == 0 then return 0 end
    return sum / maxAmp
end

-- Ridge noise: для горных хребтов (1 - |perlin|)².
function perlin:ridge2d(x, y, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0.5
    lacunarity = lacunarity or 2.0
    local sum = 0
    local amplitude = 1
    local frequency = 1
    local maxAmp = 0
    for _ = 1, octaves do
        local n = 1 - math.abs(self:noise2d(x * frequency, y * frequency))
        n = n * n
        sum = sum + n * amplitude
        maxAmp = maxAmp + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end
    if maxAmp == 0 then return 0 end
    return sum / maxAmp -- 0..1
end
