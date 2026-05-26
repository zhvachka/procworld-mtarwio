-- Генератор одного чанка: heightmap → DFF + COL spec для mtarwio.buildShell.

chunk = {}

local sqrt, floor, min, max, abs = math.sqrt, math.floor, math.min, math.max, math.abs

local function smoothstep(a, b, x)
    if x <= a then return 0 end
    if x >= b then return 1 end
    local t = (x - a) / (b - a)
    return t * t * (3 - 2 * t)
end

-- Радиальное распределение биомов: плато → холмы → горы от центра к краю.
local function radialBands(wx, wy, cfg)
    local halfWorld = cfg.chunksPerSide * cfg.chunkSize * 0.5
    local dx = wx - halfWorld
    local dy = wy - halfWorld
    local norm = min(1, sqrt(dx * dx + dy * dy) / halfWorld)
    local rf = cfg.radialFalloff
    local po, ho, of = rf.plateauOuter, rf.hillsOuter, rf.outerFraction

    local plateau   = 1 - smoothstep(po * 0.7, po, norm)
    local hillsRise = smoothstep(po * 0.8, (po + ho) * 0.5, norm)
    local hillsFall = 1 - smoothstep((po + ho) * 0.5, ho, norm)
    local hills     = min(hillsRise, hillsFall)
    local mountain  = smoothstep(ho, of, norm)
    return plateau, hills, mountain
end

local function sampleHeight(noiseGen, wx, wy, cfg)
    local nh, nr, nw = noiseGen.height, noiseGen.ridge, cfg.noise.warp
    local plateau, hills, mountain = radialBands(wx, wy, cfg)

    local base = noiseGen.heightInstance:fractal2d(
        wx * nh.scale, wy * nh.scale,
        nh.octaves, nh.persistence, nh.lacunarity
    ) * nh.amplitude

    local plateauBoost = plateau * cfg.plateauHeight

    -- Domain-warped ridge даёт извилистые гряды вместо радиально-симметричных.
    local warpX, warpY = 0, 0
    if hills + mountain > 0 then
        warpX = noiseGen.warpInstance:fractal2d(
            wx * nw.scale, wy * nw.scale,
            nw.octaves, nw.persistence, nw.lacunarity
        ) * nw.amplitude
        warpY = noiseGen.warpInstance:fractal2d(
            wx * nw.scale + 137.7, wy * nw.scale - 89.3,
            nw.octaves, nw.persistence, nw.lacunarity
        ) * nw.amplitude
    end

    local ridgeN = 0
    if hills + mountain > 0 then
        ridgeN = noiseGen.ridgeInstance:ridge2d(
            (wx + warpX) * nr.scale, (wy + warpY) * nr.scale,
            nr.octaves, nr.persistence, nr.lacunarity
        )
    end

    local hillsRise    = hills    > 0 and (max(0, ridgeN - 0.35) / 0.65 * 18 * hills) or 0
    local mountainRise = mountain > 0 and (max(0, ridgeN - 0.5 ) / 0.5  * nr.amplitude * mountain) or 0

    local rb = noiseGen.riverbedInstance:fractal2d(
        wx * cfg.noise.riverbed.scale, wy * cfg.noise.riverbed.scale,
        cfg.noise.riverbed.octaves, cfg.noise.riverbed.persistence, cfg.noise.riverbed.lacunarity
    )
    local riverFactor = 1 - min(1, abs(rb) * 12)
    local riverWeight = (1 - plateau * 0.85) * (1 - mountain * 0.7)
    local riverDepth = riverFactor > 0 and (riverFactor * 8 * riverWeight) or 0

    local height = base + plateauBoost + hillsRise + mountainRise - riverDepth

    -- Внутри плато (>0.5) поднимаем высоту до seaLevel+1, чтобы там не появлялись лужи.
    if plateau > 0.5 then
        local minHere = cfg.seaLevel + 1
        if height < minHere then
            local t = (plateau - 0.5) * 2
            height = height + (minHere - height) * t
        end
    end
    return height
end

local function sampleMoisture(noiseGen, wx, wy, cfg)
    local nm = cfg.noise.moisture
    return noiseGen.moistureInstance:fractal2d(
        wx * nm.scale, wy * nm.scale,
        nm.octaves, nm.persistence, nm.lacunarity
    )
end

local function buildHeightmap(cx, cy, noiseGen, cfg)
    local resolution = cfg.chunkResolution
    local chunkSize  = cfg.chunkSize
    local step       = chunkSize / resolution
    local heights, moisture = {}, {}
    for iy = 0, resolution do
        local rowH, rowM = {}, {}
        local wy = cy * chunkSize + iy * step
        for ix = 0, resolution do
            local wx = cx * chunkSize + ix * step
            rowH[ix] = sampleHeight(noiseGen, wx, wy, cfg)
            rowM[ix] = sampleMoisture(noiseGen, wx, wy, cfg)
        end
        heights[iy]  = rowH
        moisture[iy] = rowM
    end
    return heights, moisture, step
end

local function normalize3(x, y, z)
    local l = sqrt(x * x + y * y + z * z)
    if l <= 1e-6 then return 0, 0, 1 end
    return x / l, y / l, z / l
end

local function slopeAt(heights, ix, iy, step, resolution)
    local hL = heights[iy][max(0, ix - 1)]
    local hR = heights[iy][min(resolution, ix + 1)]
    local hD = heights[max(0, iy - 1)][ix]
    local hU = heights[min(resolution, iy + 1)][ix]
    local dx = (hR - hL) / (2 * step)
    local dy = (hU - hD) / (2 * step)
    return min(1, sqrt(dx * dx + dy * dy))
end

function chunk.generate(cx, cy, noiseGen, cfg)
    local resolution = cfg.chunkResolution
    local chunkSize  = cfg.chunkSize
    local heights, moistureMap, step = buildHeightmap(cx, cy, noiseGen, cfg)

    local halfChunk = chunkSize * 0.5
    local vBright   = cfg.terrainVertexBrightness or 0.85
    local uvTile    = cfg.terrainUVScale or (1 / 24)

    local vertices, normals, uvs, vertexColors = {}, {}, {}, {}
    local hasWater = false
    local vertexCount = (resolution + 1) * (resolution + 1)

    local function vertexIndex(ix, iy)
        return iy * (resolution + 1) + ix + 1
    end

    -- Вершины (центрированы вокруг 0,0) + UV в мировых координатах для бесшовности.
    for iy = 0, resolution do
        for ix = 0, resolution do
            local z = heights[iy][ix]
            vertices[#vertices + 1] = { ix * step - halfChunk, iy * step - halfChunk, z }
            normals[#normals + 1]   = { 0, 0, 1 }
            local wx = cx * chunkSize + ix * step
            local wy = cy * chunkSize + iy * step
            uvs[#uvs + 1] = { wx * uvTile, wy * uvTile }
            if z < cfg.seaLevel then hasWater = true end
        end
    end

    -- Треугольники с шахматным split-ом — более естественные нормали.
    local faces = {}
    for iy = 0, resolution - 1 do
        for ix = 0, resolution - 1 do
            local v00 = vertexIndex(ix,     iy)
            local v10 = vertexIndex(ix + 1, iy)
            local v01 = vertexIndex(ix,     iy + 1)
            local v11 = vertexIndex(ix + 1, iy + 1)
            if (ix + iy) % 2 == 0 then
                faces[#faces + 1] = { v00, v10, v11 }
                faces[#faces + 1] = { v00, v11, v01 }
            else
                faces[#faces + 1] = { v00, v10, v01 }
                faces[#faces + 1] = { v10, v11, v01 }
            end
        end
    end

    -- Per-vertex нормали — накопление по соседним треугольникам.
    local accumNX, accumNY, accumNZ = {}, {}, {}
    for i = 1, vertexCount do
        accumNX[i] = 0; accumNY[i] = 0; accumNZ[i] = 0
    end
    for f = 1, #faces do
        local face = faces[f]
        local a, b, c = vertices[face[1]], vertices[face[2]], vertices[face[3]]
        local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
        local nx = uy * vz - uz * vy
        local ny = uz * vx - ux * vz
        local nz = ux * vy - uy * vx
        for k = 1, 3 do
            local idx = face[k]
            accumNX[idx] = accumNX[idx] + nx
            accumNY[idx] = accumNY[idx] + ny
            accumNZ[idx] = accumNZ[idx] + nz
        end
    end
    for i = 1, vertexCount do
        local nx, ny, nz = normalize3(accumNX[i], accumNY[i], accumNZ[i])
        normals[i] = { nx, ny, nz }
    end

    -- Per-vertex biome color → DIFFUSE, текстура модулирует через bModulateMaterialColor.
    for iy = 0, resolution do
        for ix = 0, resolution do
            local idx = vertexIndex(ix, iy)
            local h = heights[iy][ix]
            local m = moistureMap[iy][ix]
            local s = slopeAt(heights, ix, iy, step, resolution)
            local _, color = biome.classify(h, m, s, cfg)
            local r, g, b = color[1], color[2], color[3]
            if vBright ~= 1 then
                r = r * vBright; g = g * vBright; b = b * vBright
            end
            if r < 0 then r = 0 elseif r > 255 then r = 255 end
            if g < 0 then g = 0 elseif g > 255 then g = 255 end
            if b < 0 then b = 0 elseif b > 255 then b = 255 end
            vertexColors[idx] = { floor(r + 0.5), floor(g + 0.5), floor(b + 0.5), color[4] or 255 }
        end
    end

    local terrainSpec = {
        vertices     = vertices,
        faces        = faces,
        normals      = normals,
        uvs          = uvs,
        vertexColors = vertexColors,
        materials = {
            { name = "terrain", color = {255,255,255,255}, textureName = "proc_terrain" },
        },
        materialLighting = cfg.materialLighting,
        geometryFlags    = cfg.geometryFlags,
        name             = string.format("chunk_%d_%d", cx, cy),
        colVersion       = cfg.colVersion or "COLL",
        colSurface       = cfg.colSurface,
        colShadow        = cfg.colShadow,
    }

    -- LOD spec — упрощённая сетка с теми же UV и текстурой.
    local lodSpec
    if cfg.lodResolution and cfg.lodResolution >= 2 then
        local lodRes  = cfg.lodResolution
        local lodStep = chunkSize / lodRes

        local function heightAt(localX, localY)
            local fx = max(0, min(resolution, localX / step))
            local fy = max(0, min(resolution, localY / step))
            local ix = floor(fx); local iy = floor(fy)
            local tx = fx - ix;   local ty = fy - iy
            local ix1 = min(resolution, ix + 1)
            local iy1 = min(resolution, iy + 1)
            local h00 = heights[iy][ix];  local h10 = heights[iy][ix1]
            local h01 = heights[iy1][ix]; local h11 = heights[iy1][ix1]
            local hx0 = h00 + (h10 - h00) * tx
            local hx1 = h01 + (h11 - h01) * tx
            return hx0 + (hx1 - hx0) * ty
        end

        local function coarseSlope(lx, ly)
            local h  = heightAt(lx, ly)
            local hR = heightAt(lx + lodStep, ly)
            local hU = heightAt(lx, ly + lodStep)
            local dx = (hR - h) / lodStep
            local dy = (hU - h) / lodStep
            return min(1, sqrt(dx * dx + dy * dy))
        end

        local lodBright = cfg.colorBrightness or 0.7
        local lodVerts, lodNormals, lodColors, lodFaces, lodUVs = {}, {}, {}, {}, {}
        for iy = 0, lodRes do
            for ix = 0, lodRes do
                local sx = ix * lodStep
                local sy = iy * lodStep
                local h  = heightAt(sx, sy)
                local mx = max(0, min(resolution, sx / step))
                local my = max(0, min(resolution, sy / step))
                local m  = moistureMap[floor(my)] and moistureMap[floor(my)][floor(mx)] or 0
                local sl = coarseSlope(sx, sy)
                lodVerts[#lodVerts + 1]     = { sx - halfChunk, sy - halfChunk, h }
                lodNormals[#lodNormals + 1] = { 0, 0, 1 }
                local wx = cx * chunkSize + sx
                local wy = cy * chunkSize + sy
                lodUVs[#lodUVs + 1] = { wx * uvTile, wy * uvTile }
                local _, c = biome.classify(h, m, sl, cfg)
                if lodBright ~= 1 then
                    c = {
                        floor(c[1] * lodBright + 0.5),
                        floor(c[2] * lodBright + 0.5),
                        floor(c[3] * lodBright + 0.5),
                        c[4] or 255,
                    }
                end
                lodColors[#lodColors + 1] = c
            end
        end
        local function lodIdx(ix, iy) return iy * (lodRes + 1) + ix + 1 end
        for iy = 0, lodRes - 1 do
            for ix = 0, lodRes - 1 do
                local a = lodIdx(ix,     iy)
                local b = lodIdx(ix + 1, iy)
                local c = lodIdx(ix,     iy + 1)
                local d = lodIdx(ix + 1, iy + 1)
                lodFaces[#lodFaces + 1] = { a, b, d }
                lodFaces[#lodFaces + 1] = { a, d, c }
            end
        end
        lodSpec = {
            vertices     = lodVerts,
            normals      = lodNormals,
            uvs          = lodUVs,
            vertexColors = lodColors,
            faces        = lodFaces,
            materials    = {
                { name = "terrain_lod", color = {255,255,255,255}, textureName = "proc_terrain" },
            },
            materialLighting = cfg.materialLighting,
            geometryFlags    = cfg.geometryFlags,
            name = string.format("chunk_%d_%d_lod", cx, cy),
        }
    end

    -- Lazy-семплеры для растительности и спавна.
    local function bilinearHeight(localX, localY)
        local fx = max(0, min(resolution, localX / step))
        local fy = max(0, min(resolution, localY / step))
        local ix = floor(fx); local iy = floor(fy)
        local tx = fx - ix;   local ty = fy - iy
        local ix1 = min(resolution, ix + 1)
        local iy1 = min(resolution, iy + 1)
        local h00 = heights[iy][ix];  local h10 = heights[iy][ix1]
        local h01 = heights[iy1][ix]; local h11 = heights[iy1][ix1]
        local hx0 = h00 + (h10 - h00) * tx
        local hx1 = h01 + (h11 - h01) * tx
        return hx0 + (hx1 - hx0) * ty
    end

    local function localSlope(localX, localY)
        local fx = max(0, min(resolution, localX / step))
        local fy = max(0, min(resolution, localY / step))
        local ix = floor(fx); local iy = floor(fy)
        local ix1 = min(resolution, ix + 1)
        local iy1 = min(resolution, iy + 1)
        local hL = heights[iy][max(0, ix - 1)]
        local hR = heights[iy][ix1]
        local hD = heights[max(0, iy - 1)][ix]
        local hU = heights[iy1][ix]
        local dx = (hR - hL) / (2 * step)
        local dy = (hU - hD) / (2 * step)
        return min(1, sqrt(dx * dx + dy * dy))
    end

    return {
        cx = cx, cy = cy,
        terrainSpec  = terrainSpec,
        lodSpec      = lodSpec,
        hasWater     = hasWater,
        moistureMap  = moistureMap,
        resolution   = resolution,
        sampleHeight = bilinearHeight,
        localSlope   = localSlope,
    }
end
