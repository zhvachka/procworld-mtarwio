-- (height, moisture, slope) → имя биома + RGBA. Brightness применяет caller.

biome = {}

biome.colors = {
    deepWater = {  15,  40,  85, 255 },
    water     = {  38,  80, 130, 255 },
    sand      = { 165, 145,  95, 255 },
    desert    = { 175, 140,  80, 255 },
    grass     = {  55, 100,  45, 255 },
    forest    = {  28,  62,  30, 255 },
    plainsDry = { 115, 115,  60, 255 },
    rock      = {  75,  72,  65, 255 },
    snow      = { 175, 180, 190, 255 },
}

local function lerpColor(a, b, t)
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end
    return {
        math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
        math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
        math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
        255,
    }
end
biome.lerpColor = lerpColor

function biome.classify(height, moisture, slope, cfg)
    cfg = cfg or PROCWORLD_CONFIG
    local C = biome.colors
    local seaLevel  = cfg.seaLevel
    local beachBand = cfg.beachBand
    local plainsTop = cfg.plainsTop
    local hillsTop  = cfg.hillsTop

    if height < seaLevel - 1.5 then
        local depth = math.min(1, (seaLevel - 1.5 - height) / 8)
        return "deepWater", lerpColor(C.water, C.deepWater, depth)
    end
    if height < seaLevel then
        local t = (seaLevel - height) / 1.5
        return "water", lerpColor(C.water, C.deepWater, t * 0.4)
    end
    if height < seaLevel + beachBand then
        return "beach", C.sand
    end
    if slope and slope > 0.55 then
        local altT = math.min(1, math.max(0, (height - plainsTop) / (hillsTop - plainsTop + 1)))
        return "rock", lerpColor(C.rock, { 50, 48, 45, 255 }, altT)
    end
    if height < plainsTop then
        local m = moisture or 0
        local t = (height - (seaLevel + beachBand)) / (plainsTop - seaLevel - beachBand)
        if m < -0.30 then
            return "desert", lerpColor(C.desert, C.sand, math.min(1, -m - 0.30))
        end
        if m < -0.05 then
            return "plainsDry", lerpColor(C.grass, C.plainsDry, math.min(1, -m + 0.05))
        end
        if m > 0.20 then
            return "forest", lerpColor(C.grass, C.forest, math.min(1, (m - 0.20) * 2))
        end
        return "plains", lerpColor(C.grass, C.forest, t * 0.3)
    end
    if height < hillsTop then
        local t = (height - plainsTop) / (hillsTop - plainsTop)
        return "hills", lerpColor(C.forest, C.rock, t)
    end
    local mountainCap = hillsTop + 12
    local t = math.min(1, math.max(0, (height - hillsTop) / (mountainCap - hillsTop)))
    return "mountains", lerpColor(C.rock, C.snow, t)
end
