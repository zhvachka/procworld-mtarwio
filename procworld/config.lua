-- procworld defaults. Описание в README.md.

PROCWORLD_CONFIG = {
    -- Размер мира
    chunksPerSide   = 13,
    chunkSize       = 256,
    chunkResolution = 24,
    worldDimension  = 0,
    worldInterior   = 0,
    origin = { x = 0, y = 0, z = 6 },

    -- LOD
    lodEnabled       = true,
    lodResolution    = 8,
    lodDistance      = 6000,
    modelLODDistance = 6000,

    -- Шум
    noise = {
        seed     = 1337,
        height   = { scale = 0.0028, octaves = 5, persistence = 0.5,  lacunarity = 2.0, amplitude = 5  },
        ridge    = { scale = 0.0050, octaves = 4, persistence = 0.55, lacunarity = 2.1, amplitude = 55 },
        moisture = { scale = 0.0040, octaves = 3, persistence = 0.5,  lacunarity = 2.0, amplitude = 1  },
        riverbed = { scale = 0.0022, octaves = 2, persistence = 0.5,  lacunarity = 2.0, amplitude = 1  },
        warp     = { scale = 0.0015, octaves = 2, persistence = 0.5,  lacunarity = 2.0, amplitude = 60 },
    },
    radialFalloff = { plateauOuter = 0.30, hillsOuter = 0.55, outerFraction = 0.95 },
    plateauHeight = 8,

    -- Биомы (метры от origin.z)
    seaLevel  = 2,
    beachBand = 1.4,
    plainsTop = 12,
    hillsTop  = 32,

    -- Цвет / освещение
    terrainVertexBrightness = 0.5,   -- множитель vertex color основного меша
    colorBrightness         = 0.5,   -- множитель для LOD

    -- ambient ≤ 1 (иначе материал светится сам, фары не видны)
    -- diffuse  — вклад солнца + dynamic point lights (фары идут отсюда)
    materialLighting = { ambient = 0.85, diffuse = 1.0, specular = 0.0 },

    -- brightness=255 / light=255 делают face full-bright → фары не падают.
    -- 0/0 — стандарт outdoor terrain, реагирует на dynamic lighting.
    colSurface = { material = 4, flags = 0, brightness = 0, light = 0 },
    colVersion = "COLL",
    colShadow  = false,

    -- Текстура
    detailTexture  = { size = 256, rowsPerTick = 32 },
    terrainUVScale = 1 / 16,

    geometryFlags = { bLight = true, bVertexColor = true, bModulateMaterialColor = true },

    -- Видимость (всё остальное окружение — на стороне проекта)
    farClipDistance = 3000,
    fogDistance     = 3000,

    -- Растительность
    vegetation = {
        enabled         = true,
        densityPerChunk = 64,
        createLOD       = true,
        lodDistance     = 1500,
        models = {
            trees  = { 618, 620, 624, 625, 628, 638, 639, 647, 654, 655, 711, 712, 713, 714, 715, 716, 717, 718, 728, 729 },
            rocks  = { 859, 860, 861, 3930, 3931 },
            palms  = { 700, 707, 708, 819, 820 },
            bushes = { 615, 759, 760, 761, 762, 802, 834, 835 },
        },
    },

    chunksPerFrame = 6,
}
