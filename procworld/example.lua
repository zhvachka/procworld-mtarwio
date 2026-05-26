local PREFIX = "pw"

local function notify(text, r, g, b)
    outputChatBox("[procworld] " .. tostring(text), r or 200, g or 220, b or 200)
end

local function ensureCamera() setCameraTarget(localPlayer) end

local function runStart(label)
    local cfg = procworld.getConfig()
    local n   = cfg.chunksPerSide
    notify(string.format("%s: %dx%d = %d чанков...", label, n, n, n * n), 160, 200, 240)

    local tStart = getTickCount()
    procworld.start(cfg, function(count)
        local elapsed = (getTickCount() - tStart) * 0.001
        notify(string.format("Готово: %d чанков за %.2f с.", count, elapsed), 120, 220, 160)
        procworld.teleportPlayer(localPlayer)
        ensureCamera()
    end)
end

addCommandHandler(PREFIX .. "gen", function() runStart("Генерация мира") end)

addCommandHandler(PREFIX .. "clear", function()
    procworld.stop()
    procworld.returnPlayer(localPlayer)
    ensureCamera()
    notify("Мир удалён, игрок возвращён в стандартный SA.", 200, 200, 120)
end)

addCommandHandler(PREFIX .. "go", function()
    if not procworld.isActive() then
        notify("Сначала /" .. PREFIX .. "gen", 230, 120, 100)
        return
    end
    procworld.teleportPlayer(localPlayer)
    ensureCamera()
    notify("Перенесён на точку спавна.", 120, 220, 160)
end)

addCommandHandler(PREFIX .. "seed", function(_, value)
    local seed = tonumber(value)
    if not seed then
        notify("/" .. PREFIX .. "seed <число>", 230, 120, 100); return
    end
    PROCWORLD_CONFIG.noise.seed = seed
    runStart("seed = " .. seed)
end)

addCommandHandler(PREFIX .. "size", function(_, value)
    local n = tonumber(value)
    if not n or n < 3 or n > 31 then
        notify("/" .. PREFIX .. "size <3..31>", 230, 120, 100); return
    end
    PROCWORLD_CONFIG.chunksPerSide = n
    runStart("size = " .. n)
end)

notify(string.format(
    "Загружен. /%sgen /%sclear /%sgo /%sseed <n> /%ssize <n>",
    PREFIX, PREFIX, PREFIX, PREFIX, PREFIX
), 120, 220, 160)
