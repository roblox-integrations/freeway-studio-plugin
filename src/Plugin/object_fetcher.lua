
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local Packages = script:FindFirstAncestor("Freeway").Packages
local CollectionService = game:GetService("CollectionService")

local t_u = require(script.Parent.tags_util)
local base64 = require(Packages.base64)

local POLL_RATE = 3 -- seconds

local BASE_URL = 'http://localhost:3000'



local object_fetcher = {
    cache = {},
    pieces = {}, 
    pieces_map = {}, 
    piece_is_wired = {},
    download_queue = {}, 
    enabled = false
}

export type Piece = {
    id: string,
    role: string, -- "asset|editable"
    type: string, --  "image|mesh|meshtexturepack|pbrpack",
    name: string,
    dir: string,
    hash: string,
    uploads: {
        {
            assetId: string,
            decalId: string,
            hash: string,
            operationId: string
        }
    },
    updatedAt: number,
    uploadedAt: number, 
    deletedAt: number
}

type PiecesSyncState = {
    updatedAt: number,
    pieces: {[string]: Piece}
}

local pieces_map = {}
local pieces_sync_state : PiecesSyncState = {
    updatedAt = -1, -- MI: Product opinion: update all wired instances on startup to the most recent pieces values
}



-- CollectionService:GetInstanceAddedSignal('wired'):Connect(function(instance)
--     update_instance_if_needed(instance)    
-- end)

-- CollectionService:GetInstanceRemovedSignal('wired'):Connect(function(instance)
--     update_instance_if_needed(instance)
-- end)


function object_fetcher:pieceHasAsset(piece)
	local hasAsset = false
	for i, upload in piece.uploads do
		if upload.hash == piece.hash then
			hasAsset = true
			break
		end
	end
	return hasAsset
end


function object_fetcher:update_instance_if_needed(instance) 
    local wires = t_u:get_instance_wires(instance)
    update_wired_instances(instance, wires)
end 

local function updateAssetIdForPieceNetwork(pieceId, hash, assetId) 
    local url = BASE_URL .. '/api/pieces/' .. pieceId .. '/uploads'
    local data = {hash=hash, assetId= "" .. assetId}
    local jsonData = HttpService:JSONEncode(data)
    local res = HttpService:PostAsync(url, jsonData)
    
    local json = HttpService:JSONDecode(res)
    return json
end

function object_fetcher:updateAssetIdForPiece(pieceId, hash, assetId)
    local status, errOrResult = pcall(updateAssetIdForPieceNetwork(pieceId, hash, assetId))
    if not status then
        return false
    else 
        return true
    end
end

local function fetchFromNetwork(piece)
    local url = BASE_URL .. '/api/pieces/' .. piece.id .. '/raw'
    print('fetchFromNetwork URL: ' .. url)
    local res = HttpService:GetAsync(url)
    local json = HttpService:JSONDecode(res)

    
    
    if piece.type == 'image' then
        local width = json['width']
        local height = json['height']
        local b64string = json['base64']
        local options = { Size = Vector2.new(width, height) }
        local editableImage = AssetService:CreateEditableImage(options)
        local decodedData = base64.decode(buffer.fromstring(b64string))
        editableImage:WritePixelsBuffer(Vector2.zero, editableImage.Size, decodedData)
        local content = Content.fromObject(editableImage)
        object_fetcher.cache[piece.id] = {object = content, hash = piece.hash}
        return content
    end
    if piece.type == 'mesh' then
        local b64string = json['base64']
        local decodedData = base64.decode(buffer.fromstring(b64string))
        local meshString = buffer.tostring(decodedData)
        local mesh = HttpService:JSONDecode(meshString)
        local em = RbxToEditableMesh(mesh)
        object_fetcher.cache[piece.id] = {object = em, hash = piece.hash}
        print('cached a mesh')
        return
    end

    print('!piece type not implemented:', piece.type)
end 

-- download queue handler

local downloadThread = task.spawn(function ()
    while true do
        if object_fetcher.enabled ~= true then 
            task.wait(0.5) 
            continue 
        end 
        if #object_fetcher.download_queue > 0 then  
            local piece = object_fetcher.download_queue[1]
            local cached =  object_fetcher.cache[piece.id]
            if cached == nil or cached.hash ~= piece.hash then 
                local status, err = pcall(fetchFromNetwork, piece)    
                if not status then
                    print('error fetchFromNetwork:', err)
                end 
            else 
--                print('skipping download, have cached version ')
            end

            table.remove(object_fetcher.download_queue, 1)
        else 
            task.wait(0.1)
        end
    end 
end)

local fetchThread = task.spawn(function()

    while true do
        if object_fetcher.enabled ~= true then 
                task.wait(0.5) 
                continue 
        end 

        local function fetchPiecesFromNetwork() 
            local res = HttpService:GetAsync(BASE_URL .. '/api/pieces')
            local json = HttpService:JSONDecode(res)
            local pieces = json :: { Piece }
            if pieces == nil then pieces = {} end
            object_fetcher.pieces = pieces

            local tmp_pieces_map = {}
            for _, p in pieces do
                tmp_pieces_map[p.id] = p
            end
            object_fetcher.pieces_map = tmp_pieces_map
            pieces_map = tmp_pieces_map
            local function process_pieces(pieces: { [string]: Piece })
                -- 1. fetch all wired instances
                local instanceWires = t_u.ts_get_all_wired_in_dm()
                local piece_is_wired = {}
                for instance, wires in instanceWires do
                    for piece_id, _ in wires do
                        piece_is_wired[piece_id] = true
                    end 
                end
                object_fetcher.piece_is_wired = piece_is_wired
                
                -- 2. update wired instance when needed and cleanup wires for missing pieces
                local maxTimestamp = -1
                for instance, wires in instanceWires do
                    local ts = update_wired_instances(instance, wires)
                    --print('ts ' .. ts .. ', maxTs ' .. maxTimestamp)
                    if ts > maxTimestamp then maxTimestamp = ts end
                end
                
                -- -- 3. update the timestamp
                -- pieces_sync_state.updatedAt = os.time()
                -- for _, p in pieces_map do
                --     -- print('piece: ' .. p.name .. ', time diff: ' .. (pieces_sync_state.updatedAt - p.updatedAt))
                -- end
            end
            process_pieces(tmp_pieces_map)
        end

        local RunService = game:GetService("RunService")
        if not RunService:IsRunning() then 
            local status, err = pcall(fetchPiecesFromNetwork)    
            if not status then
                -- MI bubble the error up, display in UI
                print('error fetching pieces', err)
            end
            print('tick, is running ', RunService:IsRunning(), RunService:IsRunMode()) -- TODO MI Why it doesn't detect it's running?
        end
        task.wait(POLL_RATE)
    
    end

end)


function RbxToEditableMesh(rbxMesh):EditableMesh 
	local em = AssetService:CreateEditableMesh({})
	local vID, uvID, nID, fID = {}, {}, {}, {} 
	local id = 0
	for _, v in rbxMesh.v do
		id = em:AddVertex(Vector3.new(v[1], v[2], v[3]))
		table.insert(vID, id)	
	end

	for _, uv in rbxMesh.uv do
		id = em:AddUV(Vector2.new(uv[1], uv[2]))
		table.insert(uvID, id)
	end

	for _, vn in rbxMesh.vn do
		id = em:AddNormal(Vector3.new(vn[1], vn[2], vn[3]))
		table.insert(nID, id)
	end

	for _, face in rbxMesh.faces do
		-- v1[/vt1][/vn1] v2[/vt2][/vn2] v3[/vt3][/vn3] ...
		if #face.v ~= 3 then print('not a tri-face, return') end		
		id = em:AddTriangle(vID[face.v[1][1]], vID[face.v[2][1]], vID[face.v[3][1]])
		table.insert(fID, id)
		em:SetFaceUVs(id, {uvID[face.v[1][2]], uvID[face.v[2][2]], uvID[face.v[3][2]]})
		em:SetFaceNormals(id, {nID[face.v[1][3]], nID[face.v[2][3]],nID[face.v[3][3]]})
	end
	return em
end

function object_fetcher:fetch(piece)
    local obj = self.cache[piece.id]
    
--    print('fetch piece with id and hash: ', piece.id, piece.hash)

    if obj ~= nil and obj.hash == piece.hash then 
        --print('returning cached version')
        return obj.object 
    end

    print('add piece to queue: ', piece.id)
    table.insert(self.download_queue, piece)
    return nil


end



function get_current_asset_id(piece: Piece): string
    for _, upload in piece.uploads do
        if piece.hash ~= upload.hash then continue end
        return upload.assetId
    end
    return nil
end

function get_piece_update_time(piece: Piece): number 
    print('get_piece_update_time: ' .. piece.id)
    local uploadedAt = nil 
    if (piece.uploadedAt ~= nil) then uploadedAt = piece.uploadedAt else uploadedAt = piece.updatedAt end
    print('updatedAt: ' .. piece.updatedAt .. ', uploadedAt: ' .. uploadedAt)
    if(piece.updatedAt > uploadedAt) 
        then return piece.updatedAt
        else return uploadedAt
    end

end

function update_wired_instances(instance: Instance, wires: {}): number
    local needsTagsUpdate = false
    local maxTimestamp = -1;
    for piece_id, propertyName in wires do 
        -- 1. check if the piece still exists and was recently updated
        local piece = pieces_map[piece_id]
        if piece == nil then
            print('remove a wire with non-existent piece_id: ' .. piece_id)
            wires[piece_id] = nil -- remove wire for missing piece
            needsTagsUpdate = true
            continue
        end
        -- 2. Update wired instance according to the piece type
        -- 2.1 image        
        if piece.type == 'image' then
            if piece.role == 'asset' then -- TODO MI rethink this logic, roles are not the way we thought of them at the start
                local assetId = get_current_asset_id(piece)
                if assetId == nil then 
                    --print('cant find asset id for piece')
                    continue 
                end
                local assetUrl = 'rbxassetid://' .. assetId
                if(instance[propertyName] ~= assetUrl) then -- only update the property if changed
                    --print('updating ', propertyName, ' to ', assetUrl)
                    instance[propertyName] = assetUrl
                end
            else 
                print('! Unsupported role ' .. piece.role .. ' for piece type: ' .. piece.type)
            end

            -- todo editable 
        elseif piece.type == 'mesh' then
            local hasAsset = object_fetcher:pieceHasAsset(piece)
            local newMeshPart
            if not hasAsset then
                local em = object_fetcher:fetch(piece)
                if em == nil then
                    print('cant fetch mesh to set', piece.id)
                    continue
                end
                print('about to apply mesh')

                newMeshPart = AssetService:CreateMeshPartAsync(Content.fromObject(em))
            else
                local assetId = get_current_asset_id(piece)
                local assetUrl = 'rbxassetid://' .. assetId
                newMeshPart = AssetService:CreateMeshPartAsync(Content.fromUri(assetUrl))
            end
            instance.Size = newMeshPart.MeshSize
            instance:ApplyMesh(newMeshPart)

        else
            print('! Unsupported Piece type: ' .. piece.type)
        end
    end
    -- 4. persist current wiring config to tags
    if needsTagsUpdate then 
        print('tags need update!')
        t_u:set_instance_wires(instance, wires) 
    end

    return maxTimestamp
end


-- function object_fetcher:pause()
--     task.pause(downloadThread)
--     task.pause(fetchThread)
-- end

-- function object_fetcher:pause()
--     task.re(downloadThread)
--     task.pause(fetchThread)
-- end

function object_fetcher:setEnabled(enabled)
    print("object_fetcher:setEnabled: ", enabled)
    self.enabled = enabled
end

function object_fetcher:stop()
    task.cancel(downloadThread)
    task.cancel(fetchThread)

end



return object_fetcher