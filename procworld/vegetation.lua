-- Растительность: jittered-grid размещение деревьев/камней/кустов по биому.
-- Детерминированный RNG от (seed, cx, cy). Опционально вторая копия с
-- isLowLOD=true для горизонта (привязка через setLowLODElement).

vegetation = {}

local function makeRng(a, b, c, d)
    local state = (a * 2654435761 + b * 73856093 + c * 19349663 + d * 83492791) % 4294967296
    if state == 0 then state = 1 end
    return {
        state = state,
        next  = function(self)
            self.state = (self.state * 1664525 + 1013904223) % 4294967296
            return self.state
        end,
        float = function(self) return self:next() / 4294967296 end,
        pick  = function(self, list)
            if type(list) ~= "table" or #list == 0 then return nil end
            return list[(self:next() % #list) + 1]
        end,
    }
end

local function classifyAt(height, slope, moisture, cfg)
    if height < cfg.seaLevel + 0.2           then return "water"  end
    if height < cfg.seaLevel + cfg.beachBand then return "beach"  end
    if slope and slope > 0.55                then return "rock"   end
    if height < cfg.plainsTop then
        if (moisture or 0) >  0.20 then return "forest" end
        if (moisture or 0) < -0.30 then return "desert" end
        if (moisture or 0) < -0.05 then return "dry"    end
        return "plains"
    end
    if height < cfg.hillsTop then return "hills" end
    return "mountain"
end

local function spawnVegObject(modelId, x, y, z, rot, cfg)
    local main = createObject(modelId, x, y, z, 0, 0, rot, false)
    if not main then return nil end
    setElementDimension(main, cfg.worldDimension or 0)
    setElementInterior(main,  cfg.worldInterior  or 0)

    if cfg.vegetation.createLOD and setLowLODElement then
        local lod = createObject(modelId, x, y, z, 0, 0, rot, true)
        if lod then
            setElementDimension(lod, cfg.worldDimension or 0)
            setElementInterior(lod,  cfg.worldInterior  or 0)
            if engineSetModelLODDistance then
                engineSetModelLODDistance(modelId, cfg.vegetation.lodDistance or 1500, true)
            end
            setLowLODElement(main, lod)
            procworld.vegetationObjects[#procworld.vegetationObjects + 1] = lod
        end
    end
    procworld.vegetationObjects[#procworld.vegetationObjects + 1] = main
    return main
end

local function pickModelForBiome(biomeName, rng, models)
    if biomeName == "water" then return nil end

    if biomeName == "beach" then
        if rng:float() < 0.30 then return rng:pick(models.palms) end
        return nil
    end
    if biomeName == "desert" then
        if rng:float() < 0.15 then return rng:pick(models.bushes) end
        return nil
    end
    if biomeName == "rock" or biomeName == "mountain" then
        if rng:float() < 0.60 then
            if rng:float() < 0.85 then return rng:pick(models.rocks)
            else                       return rng:pick(models.bushes) end
        end
        return nil
    end
    if biomeName == "hills" then
        if rng:float() < 0.75 then
            local r = rng:float()
            if r < 0.75 then return rng:pick(models.trees)
            elseif r < 0.90 then return rng:pick(models.rocks)
            else return rng:pick(models.bushes) end
        end
        return nil
    end
    if biomeName == "dry" then
        if rng:float() < 0.35 then return rng:pick(models.bushes) end
        return nil
    end
    if biomeName == "forest" then
        if rng:float() < 0.90 then
            if rng:float() < 0.78 then return rng:pick(models.trees)
            else                       return rng:pick(models.bushes) end
        end
        return nil
    end
    if biomeName == "plains" then
        if rng:float() < 0.45 then
            if rng:float() < 0.6 then return rng:pick(models.trees)
            else                      return rng:pick(models.bushes) end
        end
    end
    return nil
end

function vegetation.populateChunk(cfg, entry)
    local cs       = cfg.chunkSize
    local seed     = cfg.noise.seed
    local density  = cfg.vegetation.densityPerChunk or 25
    local models   = cfg.vegetation.models or {}
    local gridN    = math.max(2, math.floor(math.sqrt(density) + 0.5))
    local cellSize = cs / gridN

    local rng = makeRng(seed, entry.cx + 1, entry.cy + 1, gridN * 7)

    for gy = 0, gridN - 1 do
        for gx = 0, gridN - 1 do
            local jx = rng:float() * 0.92 + 0.04
            local jy = rng:float() * 0.92 + 0.04
            local localX = (gx + jx) * cellSize
            local localY = (gy + jy) * cellSize

            local h     = entry.sampleHeight(localX, localY)
            local slope = entry.localSlope and entry.localSlope(localX, localY) or 0

            local moisture = 0
            if entry.moistureMap and entry.resolution then
                local res  = entry.resolution
                local step = cs / res
                local mx   = math.floor(math.max(0, math.min(res, localX / step)))
                local my   = math.floor(math.max(0, math.min(res, localY / step)))
                moisture   = entry.moistureMap[my] and entry.moistureMap[my][mx] or 0
            end

            local biomeName = classifyAt(h, slope, moisture, cfg)
            local modelId   = pickModelForBiome(biomeName, rng, models)
            if modelId then
                spawnVegObject(
                    modelId,
                    entry.cornerX + localX,
                    entry.cornerY + localY,
                    cfg.origin.z + h - 0.2,
                    rng:float() * 360,
                    cfg
                )
            end
        end
    end
end
