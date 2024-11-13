--!strict
local Packages = script:FindFirstAncestor("PhotoshopIntegration").Packages
local React = require(Packages.React)
local Cryo = require(Packages.Cryo)

local e = React.createElement
local Selection = game:GetService("Selection")
local CollectionService = game:GetService("CollectionService")

local PieceDetailsComponent = React.Component:extend("PieceDetailsComponent")
local TextureProperties = require(script.Parent.TextureProperties)

local InstanceWirerComponent = require(script.Parent.InstanceWirerComponent)
local PluginEnum = require(script.Parent.Enum)
local t_u = require(script.Parent.tags_util)


function PieceDetailsComponent:onClickSyncButton()
	-- local state = self.state
	-- local ok, response = pcall(function()
	-- 	-- call sync long running method and return
	-- 	return false
	-- end)
	-- if not ok or not response.Success then
	-- 	if typeof(response) == "table" then
	-- 		warn("Request failed:", response.StatusCode, response.StatusMessage)
	-- 	else
	-- 		warn("Request failed:", response)
	-- 	end
	-- 	return
	-- end
end



function PieceDetailsComponent:didMount()
	print('PieceDetailsComponent:didMount', self.state.wirersModel)

    CollectionService:GetInstanceAddedSignal('wired'):Connect(function(instance)
		local updateWirersState = t_u:shouldRebuildWirersStat(Selection:Get(), instance)
		if updateWirersState then self:updateWirersState() end
    end)

    CollectionService:GetInstanceRemovedSignal('wired'):Connect(function(instance)
		local updateWirersState = t_u:shouldRebuildWirersStat(Selection:Get(), instance)
		if updateWirersState then self:updateWirersState() end
	end)

end

function PieceDetailsComponent:willUnmount()
	 print('PieceDetailsComponent:willUnmount')
	 
	--self:onClickDisconnectButton()
end

function PieceDetailsComponent:init()
	self:updateWirersState()
	self.onSelectionChanged = Selection.SelectionChanged:Connect(function()
		self:updateWirersState()
	end)
end


function PieceDetailsComponent:updateWirersState()
	local selection = Selection:Get()

	local result = {
	}
	for k, instance in selection do
		local wirerModelByType = result[instance.ClassName]
		if wirerModelByType == nil then 
			local properties = TextureProperties[instance.ClassName]
			if properties == nil then properties = {} end

			wirerModelByType = {
				instances = {},
				properties = properties
			} 
			result[instance.ClassName] = wirerModelByType
		end

		table.insert(wirerModelByType.instances, instance)
	end

	for className, wirerModel in result do
		local count = #wirerModel.instances
		if count > 1 
			then wirerModel.header = count .. ' ' .. className  .. 's' 
			else wirerModel.header = wirerModel.instances[1].Name
		end


		-- per-property wiring state -- wired to current, not wired, etc
		local properties_wire_state = {}
		for j, instance in wirerModel.instances do
			local instanceWires = t_u:get_instance_wires(instance)
			for piece_id, property in instanceWires do
				local prop_wire_st = properties_wire_state[property]
				if prop_wire_st == nil then prop_wire_st = {} end
				prop_wire_st[piece_id] = true
				properties_wire_state[property] = prop_wire_st
			end
		end


		for _, property in wirerModel.properties do -- add empty for properties that are not wired
			if properties_wire_state[property] == nil then properties_wire_state[property]  = {} end
		end

		wirerModel.combinedPropertyState = {}
		for property, wire_state in properties_wire_state do
			local count = t_u:table_size(wire_state)
			print('property->wireState', property, wire_state, count)
			
			if count == 0 then wirerModel.combinedPropertyState[property] = PluginEnum.WIRED_NOT continue  end
			if count > 1 then wirerModel.combinedPropertyState[property] = PluginEnum.WIRED_MIXED continue end
			
			if wire_state[self.props.piece.id] then wirerModel.combinedPropertyState[property] = PluginEnum.WIRED_ALL_CURRENT
			else 
				wirerModel.combinedPropertyState[property] = PluginEnum.WIRED_ALL_OTHER 
				wirerModel.combinedPropertyState['piece_id_' .. property] = Cryo.Dictionary.keys(wire_state)[1]
			end
		end	
		print('!!wireState', wirerModel.combinedPropertyState)
	end
	
	self:setState({wirersModel = result})
end

function PieceDetailsComponent.getDerivedStateFromProps(props)
	return props
end



function PieceDetailsComponent:render()
	local state = self.state
	local instanceWirers = {}

	local i = 1
	for className, wirerModel in state.wirersModel do 
		print('redo wirers')
		local newInstanceWirer = e(
			InstanceWirerComponent, 
			{
				index = i,
				instances = wirerModel.instances, 
				properties = wirerModel.properties,
				header = wirerModel.header,
				fetcher = self.props.fetcher,
				piece = self.props.piece,
				combinedPropertyState = wirerModel.combinedPropertyState,

				onClick = function(instances, propertyName)
					for _, instance in instances do
						t_u:wire_instance(instance, self.props.piece.id, propertyName)
						self.props.fetcher:update_instance_if_needed(instance)
					end
				end, 
				onUwireClick = function(instances) 
					for _, instance in instances do
						print('unwire all')

						-- TODO MI: handle properties wired to other pieces!!!
						t_u:unwire_instance(instance, self.props.piece.id)
					end
					
				end


			})
		instanceWirers['instanceWirer' .. i] = newInstanceWirer
		i = i + 1
	end
	return e("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = self.props.index, 
	}, {
		Cryo.Dictionary.join({
			uiListLayout = e("UIListLayout", {
				Padding = UDim.new(0, 0),
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}, self:renderPreviewAndName(1), instanceWirers)
	})
end


function PieceDetailsComponent:renderPreviewAndName(order: number)
	print('render piece details component')

	local content = self.props.fetcher:fetch(self.props.piece)
	return {
		e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = self.props.index, 
		}, {
		uiListLayoutTop = e("UIListLayout", {
			Padding = UDim.new(0, PluginEnum.PaddingHorizontal),
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		texturePreviewTop = content ~= nil and e("ImageLabel", {
			Size = UDim2.new(0, PluginEnum.PreviewSize, 0, PluginEnum.PreviewSize),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = PluginEnum.ColorBackground,
			BorderSizePixel = 0,
			ImageContent = content,
		}),
		-- texturePreviewTop = self.state.editableImage ~= nil and e("ImageLabel", {
		-- 	Size = UDim2.new(0, PluginEnum.PreviewSize, 0, PluginEnum.PreviewSize),
		-- 	AutomaticSize = Enum.AutomaticSize.XY,
		-- 	BackgroundColor3 = PluginEnum.ColorBackground,
		-- 	BorderSizePixel = 0,
		-- 	Image =  'http://www.roblox.com/asset/?id=699259085',
		-- }),

		nameTop = e('TextLabel', {
			Size = UDim2.new(0, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Text = self.props.piece.filePath,
			Font = Enum.Font.BuilderSansBold,
			TextSize = PluginEnum.FontSizeTextPrimary,
			TextColor3 = PluginEnum.ColorTextPrimary,
			BackgroundColor3 = PluginEnum.ColorBackground,
			BorderSizePixel = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1
		})
	})
}
end
return PieceDetailsComponent
