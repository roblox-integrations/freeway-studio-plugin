
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local Packages = script:FindFirstAncestor("PhotoshopIntegration").Packages

local t_u = require(script.Parent.tags_util)

local base64 = require(Packages.base64)
local BASE_URL = 'http://localhost:3000'
local object_fetcher = {
    cache = {},
    pieces = {}
}

export type Piece = {
    id: string,
    role: string, -- "asset|editable"
    type: string, --  "image|mesh|meshtexturepack|pbrpack"
    filePath: string,
    fileHash: string,
    uploads: {
        {
            assetId: string,
            decalId: string,
            fileHash: string,
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





coroutine.wrap(function()
    while true do
        print('Fetch!')
        local res = HttpService:GetAsync(BASE_URL .. '/api/pieces')
        local json = HttpService:JSONDecode(res)
        local pieces = json :: { Piece }
        if pieces == nil then pieces = {} end
        object_fetcher.pieces = pieces


        local tmp_pieces_map = {}
        for _, p in pieces do
            tmp_pieces_map[p.id] = p
        end
    


        local function process_pieces(pieces: { [string]: Piece })
            print('object_fetcher:process_pieces')
            pieces_map = pieces
            -- 1. fetch all wired instances
            local instanceWires = t_u.ts_get_all_wired_in_dm()
            
            -- 2. update wired instance when needed and cleanup wires for missing pieces
            local maxTimestamp = -1
            for instance, wires in instanceWires do
                local ts = update_wired_instances(instance, wires)
                print('ts ' .. ts .. ', maxTs ' .. maxTimestamp)
                if ts > maxTimestamp then maxTimestamp = ts end
            end
        
            -- -- 3. update the timestamp
            -- pieces_sync_state.updatedAt = os.time()
            -- for _, p in pieces_map do
            --     -- print('piece: ' .. p.filePath .. ', time diff: ' .. (pieces_sync_state.updatedAt - p.updatedAt))
            -- end
        end
        process_pieces(tmp_pieces_map)
        task.wait(10)
    end

end)()


function object_fetcher:fetch(piece)
    local obj = self.cache[piece.id]
    
    print('fetch piece with id and hash: ', piece.id, piece.fileHash)

    if obj ~= nil and obj.hash == piece.fileHash then 
        print('returning cached version')
        return obj.object 
    end
    
    if piece.type ~= 'image' then
        print('not an image, IMPLEMENT ME')
        return 
    end

    local url = BASE_URL .. '/api/pieces/' .. piece.id .. '/raw'
    print('URL: ' .. url)
    local res = HttpService:GetAsync(url)
    local json = HttpService:JSONDecode(res)
    local width = json['width']
    local height = json['height']
    local b64string = json['bitmap']
    local options = { Size = Vector2.new(width, height) }
    local editableImage = AssetService:CreateEditableImage(options)
    
    
    local decodedData = base64.decode(buffer.fromstring(b64string))
    
    editableImage:WritePixelsBuffer(Vector2.zero, editableImage.Size, decodedData)
    local content = Content.fromObject(editableImage)
    self.cache[piece.id] = {object = content, hash = piece.fileHash}
    return content
end







function get_current_asset_id(piece: Piece): string
    for _, upload in piece.uploads do
        if piece.fileHash ~= upload.fileHash then continue end
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
    print('instance name: ' .. instance.Name)
    print(wires)
    local maxTimestamp = -1;
    for piece_id, propertyName in wires do 
        -- 1. check if the piece still exists and was recently updated
        local piece = pieces_map[piece_id]
        if piece == nil then
            print('remove a wire with non-existent piece_id: ' .. piece_id)
            wires[piece_id] = nil -- remove wire for missing piece
            continue
        end
        -- 2. Update wired instance according to the piece type
        -- 2.1 image        
        if piece.type == 'image' then
            if piece.role == 'asset' then
                print('!!! Uncomment once assets persistance is there')
                local assetId = get_current_asset_id(piece)
                if assetId == nil then 
                    print('cant find asset id for piece')
                    continue 
                end
                local assetUrl = 'rbxassetid://' .. assetId
                if(instance[propertyName] ~= assetUrl) then -- only update the property if changed
                    print('updating ', propertyName, ' to ', assetUrl)
                    instance[propertyName] = assetUrl
                end
            else 
                print('! Unsupported role ' .. piece.role .. ' for piece type: ' .. piece.type)
            end

            -- todo editable 
        else
            print('! Unsupported Piece type: ' .. piece.type)
        end
    end

    -- 4. persist current wiring config to tags
    t_u:set_instance_wires(instance, wires)

    return maxTimestamp
end







return object_fetcher