-- procworld: публичный API. См. README.md.

procworld = {
    active            = false,
    chunks            = {},
    allocatedModelIds = {},
    freeModelIds      = {},
    waterElements     = {},
    vegetationObjects = {},
    spawnPoint        = nil,
    generatingTimer   = nil,
    noiseGen          = nil,
    terrainTxd        = nil,
    terrainTxdReady   = false,
    hooks             = {},
}

-- alias для vegetation.lua
world = procworld

local CONFIG = nil

local function chunkKey(cx, cy) return cx .. ":" .. cy end

local function requestModel()
    if #procworld.freeModelIds > 0 then
        return table.remove(procworld.freeModelIds)
    end
    local id = engineRequestModel("object")
    if id then procworld.allocatedModelIds[id] = true end
    return id
end

local function releaseModel(modelId)
    if not modelId then return end
    if engineRestoreModel then engineRestoreModel(modelId) end
    if engineRestoreCOL   then engineRestoreCOL(modelId)   end
    procworld.freeModelIds[#procworld.freeModelIds + 1] = modelId
end

local function freeAllModels()
    for id in pairs(procworld.allocatedModelIds) do
        if engineFreeModel then engineFreeModel(id)
        elseif engineRestoreModel then
            engineRestoreModel(id)
            if engineRestoreCOL then engineRestoreCOL(id) end
        end
        procworld.allocatedModelIds[id] = nil
    end
    procworld.freeModelIds = {}
end

local function setupNoiseGenerators(cfg)
    local s = cfg.noise.seed
    return {
        height           = cfg.noise.height,
        ridge            = cfg.noise.ridge,
        heightInstance   = perlin.create(s),
        ridgeInstance    = perlin.create(s + 1),
        moistureInstance = perlin.create(s + 2),
        riverbedInstance = perlin.create(s + 3),
        warpInstance     = perlin.create(s + 4),
    }
end

local function ensureTerrainTxdAsync(cfg, onReady)
    if procworld.terrainTxdReady and isElement(procworld.terrainTxd) then
        onReady(true); return
    end

    texture.buildDetailAsync(cfg, function(tex)
        if not tex then onReady(false); return end

        local raw = exports.mtarwio:buildTxd({
            { name = "proc_terrain", width = tex.width, height = tex.height, pixels = tex.pixels },
        })
        if type(raw) ~= "string" or raw == "" then
            outputDebugString("[procworld] buildTxd failed", 1)
            onReady(false); return
        end

        local txd = engineLoadTXD(raw)
        if not txd then
            local tmp = "@proc_terrain.txd"
            local f = fileCreate(tmp)
            if f then
                fileWrite(f, raw); fileClose(f)
                txd = engineLoadTXD(tmp)
                fileDelete(tmp)
            end
        end
        if not txd then
            outputDebugString("[procworld] engineLoadTXD failed", 1)
            onReady(false); return
        end

        procworld.terrainTxd      = txd
        procworld.terrainTxdReady = true
        onReady(true)
    end)
end

local function destroyTerrainTxd()
    if isElement(procworld.terrainTxd) then destroyElement(procworld.terrainTxd) end
    procworld.terrainTxd      = nil
    procworld.terrainTxdReady = false
end

local function applyEnvironment(cfg)
    if removeGameWorld then removeGameWorld() end
    if cfg.farClipDistance then setFarClipDistance(cfg.farClipDistance) end
    if cfg.fogDistance     then setFogDistance(cfg.fogDistance)         end
end

local function restoreEnvironment()
    if restoreGameWorld     then restoreGameWorld()     end
    if resetFogDistance     then resetFogDistance()     end
    if resetFarClipDistance then resetFarClipDistance() end
end

local function deployMesh(spec, worldX, worldY, worldZ, withCol, isLowLOD)
    local result = withCol
        and exports.mtarwio:buildShell(spec)
        or  exports.mtarwio:buildMesh(spec)

    local dffRaw, colRaw
    if withCol then
        if type(result) ~= "table" or not result.dffRaw then
            outputDebugString("[procworld] buildShell failed for " .. tostring(spec.name), 1)
            return nil
        end
        dffRaw, colRaw = result.dffRaw, result.colRaw
    else
        if type(result) ~= "string" or result == "" then
            outputDebugString("[procworld] buildMesh failed for " .. tostring(spec.name), 1)
            return nil
        end
        dffRaw = result
    end

    local modelId = requestModel()
    if not modelId then return nil end

    local dff = engineLoadDFF(dffRaw)
    if not dff then
        releaseModel(modelId)
        return nil
    end

    -- TXD должен быть импортирован ДО engineReplaceModel, иначе textureName не резолвится.
    if isElement(procworld.terrainTxd) then
        engineImportTXD(procworld.terrainTxd, modelId)
    end

    -- COL ставим ДО engineReplaceModel — иначе движок периодически удерживает старую коллизию.
    local col
    if colRaw then
        col = engineLoadCOL(colRaw)
        if col then engineReplaceCOL(col, modelId) end
    end

    engineReplaceModel(dff, modelId)
    if engineSetModelLODDistance then
        engineSetModelLODDistance(modelId, CONFIG.modelLODDistance or 6000, true)
    end

    local obj = createBuilding(modelId, worldX, worldY, worldZ, 0, 0, 0)
    if not obj then
        releaseModel(modelId)
        if isElement(dff) then destroyElement(dff) end
        if isElement(col) then destroyElement(col) end
        return nil
    end

    --[[setElementDimension(obj, CONFIG.worldDimension or 0)
    setElementInterior(obj, CONFIG.worldInterior or 0)
    setElementDoubleSided(obj, true)

    -- LOD: отключаем стриминг, иначе MTA выгружает их frustum-culling-ом под углом.
    if isLowLOD and setElementStreamable then
        setElementStreamable(obj, false)
    end

    -- Повторяем engineReplaceCOL после createObject — известная задержка применения COL.
    if col then engineReplaceCOL(col, modelId) end]]

    return { object = obj, dff = dff, col = col, modelId = modelId }
end

local function worldOffset(cfg)
    local total = cfg.chunksPerSide * cfg.chunkSize
    return cfg.origin.x - total * 0.5, cfg.origin.y - total * 0.5
end

local function createChunkWaterTile(cfg, worldX, worldY)
    local s = cfg.chunkSize
    local z = cfg.origin.z + cfg.seaLevel + 0.3
    local water = createWater(
        worldX,     worldY,     z,
        worldX + s, worldY,     z,
        worldX,     worldY + s, z,
        worldX + s, worldY + s, z,
        false
    )
    if water then
        setElementDimension(water, cfg.worldDimension)
        setElementInterior(water,  cfg.worldInterior)
        procworld.waterElements[#procworld.waterElements + 1] = water
    end
end

local function buildOneChunk(cx, cy, cfg)
    local data = chunk.generate(cx, cy, procworld.noiseGen, cfg)
    local offX, offY = worldOffset(cfg)
    local half = cfg.chunkSize * 0.5
    local cornerX = offX + cx * cfg.chunkSize
    local cornerY = offY + cy * cfg.chunkSize
    local wx = cornerX + half
    local wy = cornerY + half
    local wz = cfg.origin.z

    local entry = {
        cx = cx, cy = cy,
        cornerX = cornerX, cornerY = cornerY,
        parts = {},
        sampleHeight = data.sampleHeight,
        localSlope   = data.localSlope,
        moistureMap  = data.moistureMap,
        resolution   = data.resolution,
        hasWater     = data.hasWater,
    }

    local terrain = deployMesh(data.terrainSpec, wx, wy, wz, true, false)
    if terrain then entry.parts[#entry.parts + 1] = terrain end

    if cfg.lodEnabled and data.lodSpec and terrain and setLowLODElement then
        local lod = deployMesh(data.lodSpec, wx, wy, wz, false, true)
        if lod and lod.object then
            if engineSetModelLODDistance then
                engineSetModelLODDistance(lod.modelId, cfg.lodDistance or 6000, true)
            end
            setLowLODElement(terrain.object, lod.object)
            entry.parts[#entry.parts + 1] = lod
        end
    end

    if data.hasWater then createChunkWaterTile(cfg, cornerX, cornerY) end

    if cfg.vegetation and cfg.vegetation.enabled and vegetation and vegetation.populateChunk then
        vegetation.populateChunk(cfg, entry)
    end

    procworld.chunks[chunkKey(cx, cy)] = entry
end

local function startGenerationQueue(cfg, onComplete)
    local n = cfg.chunksPerSide
    local queue = {}
    for cy = 0, n - 1 do
        for cx = 0, n - 1 do
            queue[#queue + 1] = { cx, cy }
        end
    end
    local total = #queue
    local cursor = 1
    local perFrame = math.max(1, cfg.chunksPerFrame or 2)

    if procworld.generatingTimer and isTimer(procworld.generatingTimer) then
        killTimer(procworld.generatingTimer)
    end

    procworld.generatingTimer = setTimer(function()
        local frameLimit = cursor + perFrame - 1
        while cursor <= total and cursor <= frameLimit do
            local pair = queue[cursor]
            buildOneChunk(pair[1], pair[2], cfg)
            cursor = cursor + 1
        end
        if cursor > total then
            if isTimer(procworld.generatingTimer) then
                killTimer(procworld.generatingTimer)
            end
            procworld.generatingTimer = nil
            if onComplete then onComplete(total) end
        end
    end, 50, 0)
end

local function computeSpawn(cfg)
    local n = cfg.chunksPerSide
    local centerCx = math.floor(n / 2)
    local centerCy = math.floor(n / 2)
    local entry = procworld.chunks[chunkKey(centerCx, centerCy)]
    local cs = cfg.chunkSize
    local offX, offY = worldOffset(cfg)
    local sx = offX + centerCx * cs + cs * 0.5
    local sy = offY + centerCy * cs + cs * 0.5
    local terrainZ = entry and entry.sampleHeight and entry.sampleHeight(cs * 0.5, cs * 0.5) or 0
    if terrainZ < cfg.seaLevel + 1 then terrainZ = cfg.seaLevel + 1 end
    return { x = sx, y = sy, z = cfg.origin.z + terrainZ + 1.5 }
end

local function destroyAllChunks()
    for _, entry in pairs(procworld.chunks) do
        for _, part in ipairs(entry.parts or {}) do
            if isElement(part.object) then destroyElement(part.object) end
            if isElement(part.dff)    then destroyElement(part.dff)    end
            if isElement(part.col)    then destroyElement(part.col)    end
            releaseModel(part.modelId)
        end
    end
    procworld.chunks = {}
end

local function destroyWater()
    for _, w in ipairs(procworld.waterElements) do
        if isElement(w) then destroyElement(w) end
    end
    procworld.waterElements = {}
end

local function destroyVegetation()
    for _, obj in ipairs(procworld.vegetationObjects) do
        if isElement(obj) then destroyElement(obj) end
    end
    procworld.vegetationObjects = {}
end

local function softReset()
    if procworld.generatingTimer and isTimer(procworld.generatingTimer) then
        killTimer(procworld.generatingTimer)
    end
    procworld.generatingTimer = nil
    destroyAllChunks()
    destroyWater()
    destroyVegetation()
    destroyTerrainTxd()
    freeAllModels()
    procworld.spawnPoint = nil
end

-- Public API ----------------------------------------------------------------

function procworld.start(cfg, onComplete)
    cfg = cfg or PROCWORLD_CONFIG
    CONFIG = cfg

    local wasActive = procworld.active
    if wasActive then softReset() end
    procworld.active = false
    procworld.noiseGen = setupNoiseGenerators(cfg)

    if not wasActive then applyEnvironment(cfg) end

    local player = localPlayer
    if isElement(player) then setElementFrozen(player, true) end

    ensureTerrainTxdAsync(cfg, function(ok)
        if not ok then
            if isElement(player) then setElementFrozen(player, false) end
            if onComplete then onComplete(0) end
            return
        end
        if procworld.hooks.onChunksStart then procworld.hooks.onChunksStart() end
        startGenerationQueue(cfg, function(total)
            procworld.spawnPoint = computeSpawn(cfg)
            procworld.active = true
            if isElement(player) then setElementFrozen(player, false) end
            if onComplete then onComplete(total) end
        end)
    end)
end

function procworld.stop()
    softReset()
    restoreEnvironment()
    procworld.active = false
end

function procworld.isActive() return procworld.active end
function procworld.getSpawn()  return procworld.spawnPoint end
function procworld.getConfig() return CONFIG or PROCWORLD_CONFIG end
function procworld.getRuntime() return procworld end

function procworld.teleportPlayer(player)
    if not procworld.active or not procworld.spawnPoint then
        return false, "Мир ещё не построен."
    end
    player = player or localPlayer
    local cfg = CONFIG or PROCWORLD_CONFIG
    setElementDimension(player, cfg.worldDimension or 0)
    setElementInterior(player, cfg.worldInterior or 0)
    setElementPosition(player, procworld.spawnPoint.x, procworld.spawnPoint.y, procworld.spawnPoint.z)
    setElementFrozen(player, false)
    local vehicle = getPedOccupiedVehicle(player)
    if vehicle then
        setElementDimension(vehicle, cfg.worldDimension or 0)
        setElementInterior(vehicle, cfg.worldInterior or 0)
        setElementPosition(vehicle, procworld.spawnPoint.x, procworld.spawnPoint.y, procworld.spawnPoint.z)
    end
    return true
end

function procworld.returnPlayer(player)
    player = player or localPlayer
    setElementDimension(player, 0)
    setElementInterior(player, 0)
    setElementPosition(player, 2488, -1666, 13.5)
    local vehicle = getPedOccupiedVehicle(player)
    if vehicle then
        setElementDimension(vehicle, 0)
        setElementInterior(vehicle, 0)
    end
    return true
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if procworld.active then
        procworld.stop()
        procworld.returnPlayer(localPlayer)
    end
end)
