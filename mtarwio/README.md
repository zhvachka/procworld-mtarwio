# mtarwio

RenderWare IO + procedural mesh/TXD/COL generator for **MTA:SA**. Read and write DFF, COL and TXD binary blobs from Lua, or build them from scratch — without external assets, without RW Analyze, without Blender.

Originally by **thisdp**; procedural-build layer and bug fixes by **zhvachka**.

## What you can do with it

- **Parse DFF / TXD / COL** from raw bytes or files (`DFFIO`, `TXDIO`, `COLIO` classes).
- **Modify geometry**: scale, rotate, translate vertices; merge multiple geometries.
- **Generate DFF from scratch** — boxes, planes, arbitrary triangle meshes — with normals, UVs, vertex colors and multiple materials.
- **Generate COL from a geometry** — automatic triangle-mesh collision.
- **Generate stub TXD** with named placeholders so `engineApplyShaderToWorldTexture` can hook into procedural models.
- **Merge many transformed instances** of one template into a single optimized DFF (useful for procedural buildings, voxel terrain, repeated props).

## Quick reference

The resource exports the high-level builders below. Add `<include resource="mtarwio" />` to your `meta.xml`.

### `buildMesh(spec) → rawDff` *or* `false, errorMessage`

Build a DFF from arbitrary triangle geometry.

```lua
local rawDff = exports.mtarwio:buildMesh({
    vertices = {
        { 0, 0, 0 }, { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 },
    },
    faces = {                   -- 1-indexed triangles
        { 1, 2, 3 },
        { 1, 3, 4 },
    },
    normals = {                 -- optional, per vertex
        { 0, 0, 1 }, { 0, 0, 1 }, { 0, 0, 1 }, { 0, 0, 1 },
    },
    uvs = {                     -- optional, per vertex; requires bound TXD
        { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 },
    },
    vertexColors = {            -- optional, per vertex, 0..255
        { 255, 0,   0,   255 },
        { 0,   255, 0,   255 },
        { 0,   0,   255, 255 },
        { 255, 255, 0,   255 },
    },
    materialIndices = { 1, 1 }, -- optional, per face (default = 1)
    materials = {               -- optional, default = one white material
        { name = "stone", color = { 200, 200, 200, 255 }, textureName = "stone" },
    },
    name = "quad",
})

local dff = engineLoadDFF(rawDff)
engineReplaceModel(dff, modelId)
```

### `buildShell(spec) → { dffRaw, colRaw, vertexCount, faceCount }`

Same input as `buildMesh`, plus generates a matching collision mesh.

```lua
local shell = exports.mtarwio:buildShell({
    vertices = ..., faces = ..., normals = ..., vertexColors = ...,
    colVersion = "COLL", -- optional, default "COLL" (SA collision v3)
})
engineReplaceModel(engineLoadDFF(shell.dffRaw), modelId)
engineReplaceCOL(engineLoadCOL(shell.colRaw), modelId)
```

### `buildBoxDff(spec) / buildBoxShell(spec)`

Convenience wrappers for axis-aligned boxes — including multi-box composites for shapes like doorway openings.

```lua
-- Single box, pivot at center-bottom (default)
local rawDff = exports.mtarwio:buildBoxDff({
    sizeX = 1.0, sizeY = 0.12, sizeZ = 3.2,
    materialName = "wall",
    pivot = "centerBottom", -- or "center"
})

-- Composite: wall with door opening
local shell = exports.mtarwio:buildBoxShell({
    materialName = "wall",
    boxes = {
        { sizeX = 0.25, sizeY = 0.12, sizeZ = 3.2, offsetX = -0.375 }, -- left jamb
        { sizeX = 0.75, sizeY = 0.12, sizeZ = 0.7,  offsetX = 0.125, offsetZ = 2.5 }, -- lintel
    },
})
```

### `buildMergedShell(templateKey, rawTemplateDff, parts, colVersion) → { dffRaw, colRaw, partCount }`

Take a small template DFF and clone it across many instances with individual position/rotation/scale, then merge everything into one optimized DFF + COL. Great for tiled terrain, voxel walls, repeated props.

```lua
local shell = exports.mtarwio:buildMergedShell(
    "fence_run",
    rawFenceDff,
    {
        { x = 0,  y = 0, z = 0, rotation = 0,  scale = 1 },
        { x = 2,  y = 0, z = 0, rotation = 0,  scale = 1 },
        { x = 4,  y = 0, z = 0, rotation = 90, scale = 1 },
    },
    "COLL"
)
```

### `buildStubTxd(names) → rawTxd`

Build a minimum-valid TXD containing 1×1 white placeholder textures with the given names. Bind it via `engineImportTXD` so `engineApplyShaderToWorldTexture(shader, name, element)` can hook a model that otherwise has no real texture data.

```lua
local rawTxd = exports.mtarwio:buildStubTxd({ "stone", "grass" })
local txd = engineLoadTXD(rawTxd)
engineImportTXD(txd, modelId)
-- engineGetModelTextureNames(modelId) now returns { "stone", "grass" }
```

## Low-level classes

When the builders aren't enough, the underlying classes are also exposed inside the resource:

- `DFFIO`, `Clump`, `Geometry`, `Material`, `Texture`, `BinMeshPLG`
- `COLIO`, `Collision`, `TVertex`, `TFace`
- `TXDIO`, `TextureDictionary`, `TextureNative`, `TextureNativeStruct`

Example: load a DFF, scale every vertex by 2, save it back:

```lua
-- (run as a script inside a resource that includes mtarwio)
local dff = DFFIO()
dff:load(rawDffBytes)
for _, vertex in ipairs(dff.clumps[1].geometryList.geometries[1].struct.vertices) do
    vertex[1] = vertex[1] * 2
    vertex[2] = vertex[2] * 2
    vertex[3] = vertex[3] * 2
end
dff:update()
local newRaw = dff:save()
```

## Coordinate conventions

- `X` — width / right
- `Y` — depth / forward
- `Z` — height / up
- Triangle winding is **counter-clockwise** when viewed from the outside (D3D / GTA SA convention).
- Default pivot for boxes is `centerBottom`: face center at `(0, 0, 0)`, the box extends up to `(±X/2, ±Y/2, sizeZ)`.

## Limitations

- TXD writer currently produces minimum-valid stub textures. To bake JPEG/PNG bytes into a real TXD with DXT compression, use `engineApplyShaderToWorldTexture` with a `dxCreateTexture` source instead — far simpler than encoding DXT in Lua.
- The DFF reader is more permissive than the writer; some exotic extensions (skinning, morph) survive a read/write round-trip only if you don't touch them.
- Collision is generated as a triangle mesh (`COLL`). No spheres / boxes / shadow meshes are emitted.

## License

MIT, same as the parent project. Pull requests welcome — see `bridge.lua` for the builder layer and `DFFStructure.lua` / `TXDStructure.lua` / `COLStructure.lua` for the low-level format code.
