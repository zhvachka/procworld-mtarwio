-- Одна процедурная greyscale-текстура. Запекается в TXD (mtarwio.buildTxd)
-- и грузится через engineImportTXD. Биом-цвет идёт vertex color, текстура
-- модулирует через bModulateMaterialColor. Periodic perlin → бесшовное тайление.

texture = {}

local function clamp255(v)
    if v < 0   then return 0   end
    if v > 255 then return 255 end
    return math.floor(v + 0.5)
end

local TEX_PERIOD = 32
local BASE_FREQ  = 32

-- Multi-octave greyscale. Светлая (~190), чтобы MODULATE с vertex_color не задушил цвет.
local function detailFill(noise, u, v)
    local n  = noise:fractal2d(u * BASE_FREQ, v * BASE_FREQ, 4, 0.5, 2.0)
    local hf = noise:noise2d(u * BASE_FREQ * 4, v * BASE_FREQ * 4)
    local t = (n + hf * 0.3) * 0.5 + 0.5
    local g = 150 + t * 80
    return clamp255(g), clamp255(g), clamp255(g)
end

texture.fills = { detail = detailFill }

-- callback({ width, height, pixels }). pixels — BGRA byte string, D3DFMT_A8R8G8B8.
function texture.buildDetailAsync(cfg, callback)
    local dt          = cfg.detailTexture or {}
    local size        = dt.size        or 256
    local rowsPerTick = dt.rowsPerTick or 32

    local noise  = perlin.createPeriodic((cfg.noise.seed or 0) + 7, TEX_PERIOD)
    local buffer = {}
    local y      = 0

    local timer
    timer = setTimer(function()
        local endY = math.min(size, y + rowsPerTick)
        for yy = y, endY - 1 do
            local v = yy / size
            for xx = 0, size - 1 do
                local u = xx / size
                local r, g, b = detailFill(noise, u, v)
                buffer[#buffer + 1] = string.char(b, g, r, 255)
            end
        end
        y = endY
        if y >= size then
            if timer and isTimer(timer) then killTimer(timer) end
            callback({ width = size, height = size, pixels = table.concat(buffer) })
        end
    end, 50, 0)
end
