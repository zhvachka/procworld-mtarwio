local templateCache = {}

local function normalizeRotation(rotation)
	local value = tonumber(rotation) or 0
	value = value % 360
	if value < 0 then
		value = value + 360
	end
	return value
end

local function updateGeometryBounds(geometry)
	if not geometry or not geometry.struct or type(geometry.struct.vertices) ~= "table" or #geometry.struct.vertices == 0 then
		return
	end

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, vertex in ipairs(geometry.struct.vertices) do
		local x = tonumber(vertex[1]) or 0
		local y = tonumber(vertex[2]) or 0
		local z = tonumber(vertex[3]) or 0
		if x < minX then minX = x end
		if y < minY then minY = y end
		if z < minZ then minZ = z end
		if x > maxX then maxX = x end
		if y > maxY then maxY = y end
		if z > maxZ then maxZ = z end
	end

	local centerX = (minX + maxX) * 0.5
	local centerY = (minY + maxY) * 0.5
	local centerZ = (minZ + maxZ) * 0.5
	local radius = 0
	for _, vertex in ipairs(geometry.struct.vertices) do
		local dx = (tonumber(vertex[1]) or 0) - centerX
		local dy = (tonumber(vertex[2]) or 0) - centerY
		local dz = (tonumber(vertex[3]) or 0) - centerZ
		local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
		if distance > radius then
			radius = distance
		end
	end

	geometry.struct.boundingSphere = { centerX, centerY, centerZ, radius }
	geometry.struct.vertexCount = #geometry.struct.vertices
	geometry.struct.faceCount = geometry.struct.faces and #geometry.struct.faces or 0
end

local function applyTransformToGeometry(geometry, offsetX, offsetY, offsetZ, rotation, scale)
	if not geometry or not geometry.struct then
		return
	end

	local angle = math.rad(normalizeRotation(rotation))
	local cosAngle = math.cos(angle)
	local sinAngle = math.sin(angle)
	local uniformScale = tonumber(scale) or 1

	if type(geometry.struct.vertices) == "table" then
		for _, vertex in ipairs(geometry.struct.vertices) do
			local x = (tonumber(vertex[1]) or 0) * uniformScale
			local y = (tonumber(vertex[2]) or 0) * uniformScale
			local z = (tonumber(vertex[3]) or 0) * uniformScale
			vertex[1] = x * cosAngle - y * sinAngle + offsetX
			vertex[2] = x * sinAngle + y * cosAngle + offsetY
			vertex[3] = z + offsetZ
		end
	end

	if type(geometry.struct.normals) == "table" then
		for _, normal in ipairs(geometry.struct.normals) do
			local x = tonumber(normal[1]) or 0
			local y = tonumber(normal[2]) or 0
			normal[1] = x * cosAngle - y * sinAngle
			normal[2] = x * sinAngle + y * cosAngle
		end
	end

	updateGeometryBounds(geometry)
end

local function loadTemplateGeometry(rawDff)
	local dff = DFFIO()
	dff:load(rawDff)
	local clump = dff.clumps and dff.clumps[1]
	if not clump or not clump.geometryList or not clump.geometryList.geometries or not clump.geometryList.geometries[1] then
		return nil, nil, "Шаблон DFF не содержит geometry."
	end
	return clump.geometryList.geometries[1], dff.version or EnumRWVersion.GTASA
end

local function getTemplate(templateKey, rawDff)
	local cached = templateCache[templateKey]
	if cached and cached.rawDff == rawDff then
		return cached
	end

	local geometry, version, geometryError = loadTemplateGeometry(rawDff)
	if not geometry then
		return nil, geometryError or "Шаблон DFF не содержит geometry."
	end

	cached = {
		rawDff = rawDff,
		version = version,
	}
	templateCache[templateKey] = cached
	return cached
end

function buildMergedShell(templateKey, rawDff, parts, colVersion, materialMap)
	if type(templateKey) ~= "string" or templateKey == "" then
		return false, "Не передан templateKey."
	end
	if type(rawDff) ~= "string" or rawDff == "" then
		return false, "Не передан raw DFF шаблона."
	end
	if type(parts) ~= "table" or #parts == 0 then
		return false, "Нет частей для сборки shell."
	end

	local template, templateError = getTemplate(templateKey, rawDff)
	if not template then
		return false, templateError or "Не удалось загрузить шаблон DFF."
	end

	local mergedGeometry = nil
	for _, part in ipairs(parts) do
		local geometry, geometryVersion, geometryError = loadTemplateGeometry(template.rawDff)
		if not geometry then
			return false, geometryError or "Не удалось подготовить geometry для merge."
		end
		if geometryVersion ~= template.version then
			geometry:convert(template.version)
		end
		applyTransformToGeometry(
			geometry,
			tonumber(part.x) or 0,
			tonumber(part.y) or 0,
			tonumber(part.z) or 0,
			tonumber(part.rotation) or 0,
			tonumber(part.scale) or 1
		)
		if not mergedGeometry then
			mergedGeometry = geometry
		else
			mergedGeometry:mergeGeometry(geometry, false)
		end
	end

	if not mergedGeometry then
		return false, "После merge не осталось geometry."
	end

	updateGeometryBounds(mergedGeometry)

	local dff = DFFIO()
	dff:createClump(template.version)
	local clump = dff.clumps[1]
	clump:addComponent()
	mergedGeometry.parent = clump.geometryList
	clump.geometryList.geometries[1] = mergedGeometry
	clump.atomics[1].struct.frameIndex = 0
	clump.atomics[1].struct.geometryIndex = 0
	clump.frameList.struct:setFrameInfoPosition(1, 0, 0, 0)
	clump.frameList.struct:setFrameInfoRotation(1, 0, 0, 0)
	clump.frameList.frames[1].frame:setName(templateKey)
	dff:update()

	local col = COLIO()
	col:generateFromGeometry(colVersion or "COLL", mergedGeometry, materialMap)

	return {
		dffRaw = dff:save(),
		colRaw = col:save(),
		partCount = #parts,
	}
end

local function appendBox(vertices, normals, texCoords, triangles, box)
	local sizeX = math.max(0.001, tonumber(box.sizeX) or 1.0)
	local sizeY = math.max(0.001, tonumber(box.sizeY) or 1.0)
	local sizeZ = math.max(0.001, tonumber(box.sizeZ) or 1.0)
	local offsetX = tonumber(box.offsetX) or 0
	local offsetY = tonumber(box.offsetY) or 0
	local offsetZ = tonumber(box.offsetZ) or 0
	local pivot = box.pivot or "centerBottom"
	local hx = sizeX * 0.5
	local hy = sizeY * 0.5
	local zMin, zMax
	if pivot == "center" then
		zMin = -sizeZ * 0.5
		zMax = sizeZ * 0.5
	else
		zMin = 0
		zMax = sizeZ
	end

	local uvScaleX = tonumber(box.uvScaleX) or 1.0
	local uvScaleY = tonumber(box.uvScaleY) or 1.0
	local uvScaleZ = tonumber(box.uvScaleZ) or 1.0

	local boxFaces = {
		{ n = { 0, 0, 1 }, verts = {
			{ -hx, -hy, zMax }, {  hx, -hy, zMax }, {  hx,  hy, zMax }, { -hx,  hy, zMax },
		}, uvs = {
			{ 0, 0 }, { sizeX * uvScaleX, 0 }, { sizeX * uvScaleX, sizeY * uvScaleY }, { 0, sizeY * uvScaleY },
		} },
		{ n = { 0, 0, -1 }, verts = {
			{ -hx,  hy, zMin }, {  hx,  hy, zMin }, {  hx, -hy, zMin }, { -hx, -hy, zMin },
		}, uvs = {
			{ 0, 0 }, { sizeX * uvScaleX, 0 }, { sizeX * uvScaleX, sizeY * uvScaleY }, { 0, sizeY * uvScaleY },
		} },
		{ n = { 1, 0, 0 }, verts = {
			{ hx, -hy, zMin }, { hx,  hy, zMin }, { hx,  hy, zMax }, { hx, -hy, zMax },
		}, uvs = {
			{ 0, sizeZ * uvScaleZ }, { sizeY * uvScaleY, sizeZ * uvScaleZ }, { sizeY * uvScaleY, 0 }, { 0, 0 },
		} },
		{ n = { -1, 0, 0 }, verts = {
			{ -hx,  hy, zMin }, { -hx, -hy, zMin }, { -hx, -hy, zMax }, { -hx,  hy, zMax },
		}, uvs = {
			{ 0, sizeZ * uvScaleZ }, { sizeY * uvScaleY, sizeZ * uvScaleZ }, { sizeY * uvScaleY, 0 }, { 0, 0 },
		} },
		{ n = { 0, 1, 0 }, verts = {
			{  hx, hy, zMin }, { -hx, hy, zMin }, { -hx, hy, zMax }, {  hx, hy, zMax },
		}, uvs = {
			{ 0, sizeZ * uvScaleZ }, { sizeX * uvScaleX, sizeZ * uvScaleZ }, { sizeX * uvScaleX, 0 }, { 0, 0 },
		} },
		{ n = { 0, -1, 0 }, verts = {
			{ -hx, -hy, zMin }, {  hx, -hy, zMin }, {  hx, -hy, zMax }, { -hx, -hy, zMax },
		}, uvs = {
			{ 0, sizeZ * uvScaleZ }, { sizeX * uvScaleX, sizeZ * uvScaleZ }, { sizeX * uvScaleX, 0 }, { 0, 0 },
		} },
	}

	for _, face in ipairs(boxFaces) do
		local baseIndex = #vertices
		for cornerIndex = 1, 4 do
			vertices[#vertices + 1] = { face.verts[cornerIndex][1] + offsetX, face.verts[cornerIndex][2] + offsetY, face.verts[cornerIndex][3] + offsetZ }
			normals[#normals + 1] = { face.n[1], face.n[2], face.n[3] }
			texCoords[#texCoords + 1] = { face.uvs[cornerIndex][1], face.uvs[cornerIndex][2] }
		end
		-- DFF face format: {Vertex2, Vertex1, MaterialID, Vertex3}
		triangles[#triangles + 1] = { baseIndex + 1, baseIndex + 0, 0, baseIndex + 2 }
		triangles[#triangles + 1] = { baseIndex + 2, baseIndex + 0, 0, baseIndex + 3 }
	end
end

local function configureBoxGeometry(geometry, spec)
	local boxes = spec.boxes
	if type(boxes) ~= "table" or #boxes == 0 then
		-- Treat spec itself as a single-box definition
		boxes = { spec }
	end

	local vertices = {}
	local normals = {}
	local texCoords = {}
	local triangles = {}
	for _, box in ipairs(boxes) do
		appendBox(vertices, normals, texCoords, triangles, box)
	end

	local struct = geometry.struct
	struct.bPosition = true
	struct.bTextured = true
	struct.bVertexColor = false
	struct.bNormal = true
	struct.bLight = true
	struct.bModulateMaterialColor = true
	struct.bTextured2 = false
	struct.bTristrip = false
	struct.bNative = false
	struct.TextureCount = 1
	struct.vertices = vertices
	struct.normals = normals
	struct.texCoords = { texCoords }
	struct.faces = triangles
	struct.vertexCount = #vertices
	struct.faceCount = #triangles
	struct.morphTargetCount = 1
	struct.hasVertices = true
	struct.hasNormals = true

	-- bounding sphere
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, vertex in ipairs(vertices) do
		if vertex[1] < minX then minX = vertex[1] end
		if vertex[2] < minY then minY = vertex[2] end
		if vertex[3] < minZ then minZ = vertex[3] end
		if vertex[1] > maxX then maxX = vertex[1] end
		if vertex[2] > maxY then maxY = vertex[2] end
		if vertex[3] > maxZ then maxZ = vertex[3] end
	end
	local centerX = (minX + maxX) * 0.5
	local centerY = (minY + maxY) * 0.5
	local centerZ = (minZ + maxZ) * 0.5
	local radius = 0
	for _, vertex in ipairs(vertices) do
		local dx = vertex[1] - centerX
		local dy = vertex[2] - centerY
		local dz = vertex[3] - centerZ
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		if d > radius then radius = d end
	end
	struct.boundingSphere = { centerX, centerY, centerZ, radius }
end

local function configureBoxMaterial(geometry, spec)
	local materialName = type(spec.materialName) == "string" and spec.materialName or "procedural_box"
	local color = spec.materialColor or { 255, 255, 255, 255 }
	local material = Material():init(geometry.version)
	material.parent = geometry.materialList
	material.struct.color = {
		math.floor(tonumber(color[1]) or 255) % 256,
		math.floor(tonumber(color[2]) or 255) % 256,
		math.floor(tonumber(color[3]) or 255) % 256,
		math.floor(tonumber(color[4]) or 255) % 256,
	}
	material.struct.isTextured = true
	material.struct.ambient = 1
	material.struct.specular = 1
	material.struct.diffuse = 1

	local texture = Texture():init(geometry.version)
	texture.parent = material
	texture.struct.flags = 0x46
	texture.textureName.string = materialName
	texture.textureName.size = math.max(4, math.ceil((#materialName + 1) / 4) * 4)
	texture.maskName.string = ""
	texture.maskName.size = 4
	material.texture = texture

	geometry.materialList.materials[1] = material
	geometry.materialList.struct.materialIndices[1] = -1
	geometry.materialList.struct.materialCount = 1

	local binMesh = BinMeshPLG()
	binMesh.parent = geometry.extension
	binMesh.type = BinMeshPLG.typeID
	binMesh.version = geometry.version
	binMesh.faceType = 0
	binMesh.materialSplitCount = 1
	binMesh.vertexCount = geometry.struct.faceCount * 3
	local indices = {}
	for triIndex, tri in ipairs(geometry.struct.faces) do
		indices[#indices + 1] = tri[2]
		indices[#indices + 1] = tri[1]
		indices[#indices + 1] = tri[4]
	end
	binMesh.materialSplits = { { binMesh.vertexCount, 0, indices } }
	binMesh:getSize()
	geometry.extension.binMeshPLG = binMesh
end

local function assembleBoxClump(spec)
	local dff = DFFIO()
	dff:createClump(EnumRWVersion.GTASA)
	local clump = dff.clumps[1]
	clump:addComponent()
	local geometry = clump.geometryList.geometries[1]
	configureBoxGeometry(geometry, spec)
	configureBoxMaterial(geometry, spec)
	clump.atomics[1].struct.frameIndex = 0
	clump.atomics[1].struct.geometryIndex = 0
	clump.frameList.struct:setFrameInfoPosition(1, 0, 0, 0)
	clump.frameList.struct:setFrameInfoRotation(1, 0, 0, 0)
	clump.frameList.frames[1].frame:setName(spec.name or "procedural_box")
	dff:update()
	return dff, geometry
end

function buildBoxDff(spec)
	if type(spec) ~= "table" then
		return false, "spec must be a table with sizeX/sizeY/sizeZ."
	end
	local dff = assembleBoxClump(spec)
	return dff:save()
end

function buildBoxShell(spec)
	if type(spec) ~= "table" then
		return false, "spec must be a table with sizeX/sizeY/sizeZ."
	end
	local dff, geometry = assembleBoxClump(spec)
	local col = COLIO()
	col:generateFromGeometry(spec.colVersion or "COLL", geometry)
	return {
		dffRaw = dff:save(),
		colRaw = col:save(),
		vertexCount = geometry.struct.vertexCount,
		faceCount = geometry.struct.faceCount,
	}
end

-- =====================================================================
-- Universal mesh builder
-- =====================================================================
-- spec:
--   vertices       = { {x,y,z}, ... }           required
--   faces          = { {i1,i2,i3}, ... }        required (1-indexed)
--   normals        = { {nx,ny,nz}, ... }        optional, per-vertex
--   uvs            = { {u,v}, ... }             optional, per-vertex
--   vertexColors   = { {r,g,b,a}, ... }         optional, per-vertex (0..255)
--   materialIndices = { matSlot, ... }          optional, per-face (1-based)
--   materials      = { {                        optional, default = 1 white material
--       name        = "matName",
--       color       = {r,g,b,a},                 (0..255)
--       textureName = "tex_name",                optional, requires bound TXD
--   }, ... }
--   name           = "frameName"                optional, default "mesh"

local function configureMeshGeometry(geometry, spec)
	local vertices = spec.vertices
	local faces = spec.faces
	local normals = spec.normals
	local uvs = spec.uvs
	local vertexColors = spec.vertexColors

	local hasNormals = type(normals) == "table" and #normals > 0
	local hasUVs = type(uvs) == "table" and #uvs > 0
	local hasVertexColors = type(vertexColors) == "table" and #vertexColors > 0

	-- Convert (1-indexed v1,v2,v3) → DFF format (0-indexed v2,v1,matID,v3)
	local triangles = {}
	for i, face in ipairs(faces) do
		local matSlot = (spec.materialIndices and spec.materialIndices[i]) or 1
		triangles[i] = {
			(face[2] or 1) - 1,
			(face[1] or 1) - 1,
			matSlot - 1,
			(face[3] or 1) - 1,
		}
	end

	-- RW GeometryStruct flags:
	--   bLight (bit 5)               — engine применяет ambient/diffuse материала + dynamic lights
	--   bVertexColor (bit 3)         — есть per-vertex colors (prelit-like)
	--   bModulateMaterialColor (bit 6) — vertex color × material.color перед lighting
	--   bNormal (bit 4)              — есть per-vertex normals (нужны для Lambert)
	--   bTextured (bit 2)            — есть UV
	-- Через spec.geometryFlags можно переопределить любой:
	--   spec.geometryFlags = { bLight=true, bModulateMaterialColor=false, ... }
	local flags = spec.geometryFlags or {}
	local function flagOr(v, def)
		if v == nil then return def end
		return v and true or false
	end

	local struct = geometry.struct
	struct.bPosition = true
	struct.bTextured = flagOr(flags.bTextured, hasUVs)
	struct.bVertexColor = flagOr(flags.bVertexColor, hasVertexColors)
	struct.bNormal = flagOr(flags.bNormal, hasNormals)
	struct.bLight = flagOr(flags.bLight, true)
	struct.bModulateMaterialColor = flagOr(flags.bModulateMaterialColor, true)
	struct.bTextured2 = flagOr(flags.bTextured2, false)
	struct.bTristrip = flagOr(flags.bTristrip, false)
	struct.bNative = flagOr(flags.bNative, false)
	struct.TextureCount = struct.bTextured and 1 or 0
	struct.vertices = vertices
	struct.vertexCount = #vertices
	struct.faces = triangles
	struct.faceCount = #triangles
	struct.morphTargetCount = 1
	struct.hasVertices = true
	struct.hasNormals = hasNormals
	if hasNormals then struct.normals = normals end
	if hasUVs then struct.texCoords = { uvs } end
	if hasVertexColors then struct.vertexColors = vertexColors end

	-- Bounding sphere
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, v in ipairs(vertices) do
		if v[1] < minX then minX = v[1] end
		if v[2] < minY then minY = v[2] end
		if v[3] < minZ then minZ = v[3] end
		if v[1] > maxX then maxX = v[1] end
		if v[2] > maxY then maxY = v[2] end
		if v[3] > maxZ then maxZ = v[3] end
	end
	local centerX = (minX + maxX) * 0.5
	local centerY = (minY + maxY) * 0.5
	local centerZ = (minZ + maxZ) * 0.5
	local radius = 0
	for _, v in ipairs(vertices) do
		local dx = v[1] - centerX
		local dy = v[2] - centerY
		local dz = v[3] - centerZ
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		if d > radius then radius = d end
	end
	struct.boundingSphere = { centerX, centerY, centerZ, radius }
end

local function configureMeshMaterials(geometry, materials, spec)
	if type(materials) ~= "table" or #materials == 0 then
		materials = { { name = "default", color = { 255, 255, 255, 255 } } }
	end
	spec = spec or {}

	for matIdx, mat in ipairs(materials) do
		local color = mat.color or { 255, 255, 255, 255 }
		local material = Material():init(geometry.version)
		material.parent = geometry.materialList
		material.struct.color = {
			math.floor(tonumber(color[1]) or 255) % 256,
			math.floor(tonumber(color[2]) or 255) % 256,
			math.floor(tonumber(color[3]) or 255) % 256,
			math.floor(tonumber(color[4]) or 255) % 256,
		}
		-- ambient / diffuse / specular — лайтинг-коэффициенты RW.
		-- ambient > 1 = модель не темнеет ночью; specular > 0 = блик.
		-- Берутся либо per-material (mat.ambient/diffuse/specular),
		-- либо из spec.materialLighting (общий блок), либо дефолт=1.
		local lighting = mat.lighting or spec.materialLighting or {}
		material.struct.ambient  = tonumber(mat.ambient  or lighting.ambient)  or 1
		material.struct.diffuse  = tonumber(mat.diffuse  or lighting.diffuse)  or 1
		material.struct.specular = tonumber(mat.specular or lighting.specular) or 1
		local texName = type(mat.textureName) == "string" and mat.textureName or nil
		material.struct.isTextured = texName ~= nil

		if texName then
			local texture = Texture():init(geometry.version)
			texture.parent = material
			texture.struct.flags = 0x46
			texture.textureName.string = texName
			texture.textureName.size = math.max(4, math.ceil((#texName + 1) / 4) * 4)
			texture.maskName.string = ""
			texture.maskName.size = 4
			material.texture = texture
		end

		geometry.materialList.materials[matIdx] = material
		geometry.materialList.struct.materialIndices[matIdx] = -1
	end
	geometry.materialList.struct.materialCount = #materials
end

local function configureMeshBinMeshPLG(geometry, faces, materialIndices, materialCount)
	-- Group face vertex indices by material slot.
	local groups = {}
	for i = 1, materialCount do
		groups[i] = {}
	end
	for faceIdx, face in ipairs(faces) do
		local matSlot = (materialIndices and materialIndices[faceIdx]) or 1
		if matSlot < 1 then matSlot = 1 end
		if matSlot > materialCount then matSlot = materialCount end
		local list = groups[matSlot]
		list[#list + 1] = (face[1] or 1) - 1
		list[#list + 1] = (face[2] or 1) - 1
		list[#list + 1] = (face[3] or 1) - 1
	end

	local binMesh = BinMeshPLG()
	binMesh.parent = geometry.extension
	binMesh.type = BinMeshPLG.typeID
	binMesh.version = geometry.version
	binMesh.faceType = 0 -- triangle list
	binMesh.materialSplitCount = materialCount
	binMesh.vertexCount = 0
	binMesh.materialSplits = {}
	for i, list in ipairs(groups) do
		binMesh.vertexCount = binMesh.vertexCount + #list
		binMesh.materialSplits[i] = { #list, i - 1, list }
	end
	binMesh:getSize()
	geometry.extension.binMeshPLG = binMesh
end

local function assembleMeshClump(spec)
	local dff = DFFIO()
	dff:createClump(EnumRWVersion.GTASA)
	local clump = dff.clumps[1]
	clump:addComponent()
	local geometry = clump.geometryList.geometries[1]
	configureMeshGeometry(geometry, spec)
	local materials = spec.materials
	if type(materials) ~= "table" or #materials == 0 then
		materials = { { name = "default" } }
	end
	configureMeshMaterials(geometry, materials, spec)
	configureMeshBinMeshPLG(geometry, spec.faces, spec.materialIndices, #materials)
	clump.atomics[1].struct.frameIndex = 0
	clump.atomics[1].struct.geometryIndex = 0
	clump.frameList.struct:setFrameInfoPosition(1, 0, 0, 0)
	clump.frameList.struct:setFrameInfoRotation(1, 0, 0, 0)
	clump.frameList.frames[1].frame:setName(spec.name or "mesh")
	dff:update()
	return dff, geometry
end

function buildMesh(spec)
	if type(spec) ~= "table" then return false, "spec must be a table" end
	if type(spec.vertices) ~= "table" or #spec.vertices == 0 then
		return false, "spec.vertices required"
	end
	if type(spec.faces) ~= "table" or #spec.faces == 0 then
		return false, "spec.faces required"
	end
	local dff = assembleMeshClump(spec)
	return dff:save()
end

-- GTA SA COL3 shadow mesh:
--   Отдельный, обычно упрощённый mesh, используемый GTA для расчёта shadow
--   volumes объекта от солнца. В отсутствие этого mesh — у объекта нет тени.
--   В большинстве случаев можно дублировать main collision (одинаковая форма,
--   меньшая deтализация даст более простую тень, но реюз main — простейший).
local function attachShadowMesh(collision, spec)
	if collision.version == "COLL" then return end
	if not spec.colShadow then return end
	collision.hasShadow = true

	local shadowSpec = (type(spec.colShadow) == "table") and spec.colShadow or nil
	local srcVerts = (shadowSpec and shadowSpec.vertices) or collision.vertices
	local srcFaces = (shadowSpec and shadowSpec.faces)    or collision.faces

	collision.shadowVertexCount = #srcVerts
	collision.shadowVertices = {}
	for i, v in ipairs(srcVerts) do
		local sv = TVertex()
		sv[1], sv[2], sv[3] = v[1], v[2], v[3]
		collision.shadowVertices[i] = sv
	end

	collision.shadowFaceCount = #srcFaces
	collision.shadowFaces = {}
	for i, f in ipairs(srcFaces) do
		local sf = TFace():init(collision.version)
		if f.a then -- уже TFace
			sf.a, sf.b, sf.c = f.a, f.b, f.c
		else
			sf.a, sf.b, sf.c = f[1] - 1, f[2] - 1, f[3] - 1
		end
		sf.surface.material   = 0
		sf.surface.flags      = 0
		sf.surface.brightness = 0
		sf.surface.light      = 1
		-- COL2/COL3 per-face material/light (см. buildShell выше).
		sf.material = 0
		sf.light    = 1
		collision.shadowFaces[i] = sf
	end
end

function buildShell(spec)
	if type(spec) ~= "table" then return false, "spec must be a table" end
	if type(spec.vertices) ~= "table" or #spec.vertices == 0 then
		return false, "spec.vertices required"
	end
	if type(spec.faces) ~= "table" or #spec.faces == 0 then
		return false, "spec.faces required"
	end
	local dff, geometry = assembleMeshClump(spec)
	local col = COLIO()
	local colVersion = spec.colVersion or "COLL"
	col:generateFromGeometry(colVersion, geometry)

	-- TSurface override: 4 байта на face. Все поля опциональны.
	--   material   — surface type (0..179): 0=DEFAULT, 1=TARMAC, 4=GRASS_LONG,
	--                12=SAND, 19=ROCK, 20=ICE и т.д. Влияет на pwd, частицы,
	--                искры, и подсветку ped/vehicle стоящих на этой грани.
	--   flags      — битфлаги TSurface (см. GTA SA modding docs).
	--   brightness — day-brightness (0..255). 255 = модель не темнеет днём.
	--   light      — night-brightness (0..255). 255 = модель не темнеет ночью.
	if spec.colSurface then
		local mat        = tonumber(spec.colSurface.material)   or 4
		local flagsByte  = tonumber(spec.colSurface.flags)      or 0
		local light      = tonumber(spec.colSurface.light)      or 1
		local brightness = tonumber(spec.colSurface.brightness) or 255
		for _, face in ipairs(col.collision.faces) do
			face.surface.material   = mat
			face.surface.flags      = flagsByte
			face.surface.brightness = brightness
			face.surface.light      = light
			-- COL2/COL3 TFace также имеет per-face material/light байты
			-- (отдельно от surface.material/surface.light), которые пишутся
			-- между индексами вершин и TSurface. Дефолтим к surface-значениям.
			face.material = mat
			face.light    = light
		end
	else
		-- Даже без явного colSurface — COL2/COL3 требует ненилевых material/light на face.
		for _, face in ipairs(col.collision.faces) do
			face.material = face.material or 0
			face.light    = face.light    or 1
		end
	end

	-- COL3 shadow mesh (optional). По умолчанию выключен.
	attachShadowMesh(col.collision, spec)

	return {
		dffRaw = dff:save(),
		colRaw = col:save(),
		vertexCount = geometry.struct.vertexCount,
		faceCount = geometry.struct.faceCount,
	}
end

local function writeRwHeader(stream, sectionType, contentSize, version)
	stream:write(sectionType, uint32)
	stream:write(contentSize, uint32)
	stream:write(version, uint32)
end

-- =====================================================================
-- buildTxd / buildStubTxd
--
-- Универсальная сборка GTA SA TXD из таблицы текстур.
--
-- Сигнатуры:
--   buildStubTxd({ "name1", "name2", ... })
--     → TXD из 1×1 белых заглушек (legacy)
--
--   buildTxd({
--     { name="proc_grass", width=256, height=256, pixels="<256*256*4 bytes BGRA>" },
--     { name="proc_sand",  width=256, height=256, pixels="..." },
--   })
--     → TXD с настоящими пикселями. Pixels = raw byte string в формате
--       D3DFMT_A8R8G8B8: 4 байта на пиксель в порядке B, G, R, A
--       (little-endian uint32 0xAARRGGBB), линии слева направо, сверху вниз.
--       Размер = width * height * 4 байт.
-- =====================================================================

local RW_STRUCT_TYPE        = 0x01
local RW_EXTENSION_TYPE     = 0x03
local RW_TEXTURENATIVE_TYPE = 0x15
local RW_TEXDICTIONARY_TYPE = 0x16
local RW_FORMAT_A8R8G8B8    = 21
local RW_DEVICE_D3D9        = 2
local RW_PLATFORM_D3D9      = 9

function buildTxd(textures)
	if type(textures) ~= "table" or #textures == 0 then
		return false, "textures must be a non-empty list of {name, width, height, pixels}"
	end

	-- Валидация и нормализация
	local items = {}
	for i, t in ipairs(textures) do
		if type(t) ~= "table" or type(t.name) ~= "string" or t.name == "" then
			return false, "texture " .. i .. ": name required"
		end
		local w = tonumber(t.width)  or 1
		local h = tonumber(t.height) or 1
		local px = t.pixels
		if type(px) ~= "string" then
			return false, "texture " .. i .. " (" .. t.name .. "): pixels must be a string"
		end
		local expected = w * h * 4
		if #px ~= expected then
			return false, string.format(
				"texture %d (%s): pixels size %d, expected %d (%dx%d×4)",
				i, t.name, #px, expected, w, h
			)
		end
		items[i] = { name = t.name:sub(1, 31), width = w, height = h, pixels = px }
	end

	local version = EnumRWVersion.GTASA
	local stream = WriteStream()

	-- Размер TextureNativeStruct content = 88 фиксированных + 4 (mipmap size) + pixelBytes
	-- TextureNative content = TextureNativeStruct(12 + content) + TextureNativeExtension(12 + 0)
	-- Все секции с TXD-уровневым 12-байтным заголовком.
	local function texNativeContentSize(item)
		return 88 + 4 + #item.pixels  -- struct content
	end
	local function texNativeTotalSize(item)
		return 12 + (12 + texNativeContentSize(item)) + (12 + 0) -- (struct) + (extension empty)
	end

	local dictStructContent = 4
	local dictExtContent    = 0
	local dictContent       = (12 + dictStructContent)
	for _, item in ipairs(items) do
		dictContent = dictContent + texNativeTotalSize(item)
	end
	dictContent = dictContent + (12 + dictExtContent)

	-- TextureDictionary section
	writeRwHeader(stream, RW_TEXDICTIONARY_TYPE, dictContent, version)

	-- TextureDictionaryStruct
	writeRwHeader(stream, RW_STRUCT_TYPE, dictStructContent, version)
	stream:write(#items, uint16)
	stream:write(RW_DEVICE_D3D9, uint16)

	-- TextureNative sections
	for _, item in ipairs(items) do
		local structContent = texNativeContentSize(item)
		writeRwHeader(stream, RW_TEXTURENATIVE_TYPE, (12 + structContent) + (12 + 0), version)

		writeRwHeader(stream, RW_STRUCT_TYPE, structContent, version)
		stream:write(RW_PLATFORM_D3D9, uint32)
		stream:write(0x1106, uint32)             -- filterFlags
		stream:write(item.name, char, 32)
		stream:write("", char, 32)               -- mask name
		stream:write(0x8200, uint32)             -- maskFlags
		stream:write(RW_FORMAT_A8R8G8B8, uint32) -- textureFormat
		stream:write(item.width, uint16)
		stream:write(item.height, uint16)
		stream:write(32, uint8)                  -- depth (bits per pixel)
		stream:write(1, uint8)                   -- mipMapCount
		stream:write(4, uint8)                   -- texCodeType
		stream:write(0x08, uint8)                -- flags (no mipmaps)
		-- Mipmap level 0
		stream:write(#item.pixels, uint32)
		stream:write(item.pixels, bytes, #item.pixels)

		-- TextureNativeExtension (empty)
		writeRwHeader(stream, RW_EXTENSION_TYPE, 0, version)
	end

	-- TextureDictionaryExtension (empty)
	writeRwHeader(stream, RW_EXTENSION_TYPE, 0, version)

	return stream:save()
end

-- Legacy: TXD из 1×1 белых заглушек по списку имён.
function buildStubTxd(textureNames)
	if type(textureNames) ~= "table" or #textureNames == 0 then
		return false, "textureNames must be a non-empty list of strings"
	end
	local stubPixel = string.char(0xFF, 0xFF, 0xFF, 0xFF)
	local items = {}
	for i, name in ipairs(textureNames) do
		items[i] = { name = tostring(name), width = 1, height = 1, pixels = stubPixel }
	end
	return buildTxd(items)
end
