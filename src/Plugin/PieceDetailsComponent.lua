--!strict
local Packages = script:FindFirstAncestor("Freeway").Packages
local React = require(Packages.React)
local Cryo = require(Packages.Cryo)

local e = React.createElement
local Selection = game:GetService("Selection")
local CollectionService = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local PieceDetailsComponent = React.Component:extend("PieceDetailsComponent")

local InstanceWirerComponent = require(script.Parent.InstanceWirerComponent)
local PluginEnum = require(script.Parent.Enum)
local t_u = require(script.Parent.tags_util)
local ui_commons = require(script.Parent.ui_commons)

function PieceDetailsComponent:didMount()
	-- print('PieceDetailsComponent:didMount', self.state.selectedWirersModel)

end

function PieceDetailsComponent:willUnmount()
	--  print('PieceDetailsComponent:willUnmount')
	 
	--self:onClickDisconnectButton()
end

function PieceDetailsComponent:init()
	self:updateSelectedWirersState()
	self.onSelectionChanged = Selection.SelectionChanged:Connect(function()
		self:updateSelectedWirersState()
	end)
	self:updateDMWirerState()

	CollectionService:GetInstanceAddedSignal('wired'):Connect(function(instance)
		local updateWirersState = t_u:shouldRebuildWirersStat(Selection:Get(), instance)
		if updateWirersState then self:updateSelectedWirersState() end
		self:updateDMWirerState()


    end)

    CollectionService:GetInstanceRemovedSignal('wired'):Connect(function(instance)
		local updateWirersState = t_u:shouldRebuildWirersStat(Selection:Get(), instance)
		if updateWirersState then self:updateSelectedWirersState() end

		self:updateDMWirerState()
	end)


end

function PieceDetailsComponent:buildWirersModel(instances) 
	return ui_commons:buildWirersModel(instances, self.props.piece.type, self.props.piece.id)
end

function PieceDetailsComponent:updateDMWirerState()
	local instancesToWires = t_u.ts_get_all_wired_in_dm()
	local instancesWiredToCurrentPiece = {}
	for instance, wires in instancesToWires do
		if wires[self.props.piece.id] ~= nil then table.insert(instancesWiredToCurrentPiece, instance) end
	end
	local result = self:buildWirersModel(instancesWiredToCurrentPiece)
	self:setState({dmWirersModel = result})
end


function PieceDetailsComponent:updateSelectedWirersState()
	local selection = Selection:Get()
	local result = self:buildWirersModel(selection)
	self:setState({selectedWirersModel = result})
end

function PieceDetailsComponent.getDerivedStateFromProps(props)
	return props
end

function PieceDetailsComponent:buildInstanceWirerComponent(i, wirerModel, showSelectButton)
	return e(
		InstanceWirerComponent, 
		{
			index = i,
			instances = wirerModel.instances, 
			properties = wirerModel.properties,
			header = wirerModel.header,
			fetcher = self.props.fetcher,
			piece = self.props.piece,
			showSelectButton = showSelectButton,
			combinedPropertyState = wirerModel.combinedPropertyState,

			onClick = function(instances, propertyName)
				local recordingId = ChangeHistoryService:TryBeginRecording('wire')
				for _, instance in instances do
					-- print('wire instance', instance, self.props.piece.id, propertyName)
					t_u:wire_instance(instance, self.props.piece.id, propertyName)
					self.props.fetcher:update_instance_if_needed(instance)
				end
				ChangeHistoryService:FinishRecording(recordingId, Enum.FinishRecordingOperation.Commit)
			end, 
			onUwireClick = function(instances, propertyName) 
				local recordingId = ChangeHistoryService:TryBeginRecording('wire')

				for _, instance in instances do
					-- print('unwire all')
					t_u:unwire_instance(instance, propertyName)
				end
				ChangeHistoryService:FinishRecording(recordingId, Enum.FinishRecordingOperation.Commit)

			end
		})
end

function PieceDetailsComponent:render()
	local state = self.state

	local selectionInstanceWirers = {}
	local dmInstanceWirers = {}


	local i = 3 
	local hasSelectionToWire = false
	for _, wirerModel in state.selectedWirersModel do 
		-- print('redo wirers')
		local newInstanceWirer = self:buildInstanceWirerComponent(i, wirerModel, false)
		selectionInstanceWirers['selectionInstanceWirer' .. i] = newInstanceWirer
		hasSelectionToWire = true
		i = i + 1
	end

	local dmWirersLabelIndex = i + 1
	local hasDMWires = false
	i = i + 2 
	for _, wirerModel in state.dmWirersModel do 
		local newInstanceWirer = self:buildInstanceWirerComponent(i, wirerModel, true)
		dmInstanceWirers['selectionInstanceWirer' .. i] = newInstanceWirer

		hasDMWires = true
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
				Padding = UDim.new(0, 10),
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalFlex = Enum.UIFlexAlignment.Fill

			}),
		}, self:renderPreviewAndName(1), 
		{
				selectedHeader = hasSelectionToWire and  e("TextLabel", {
				Size = UDim2.new(0, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				LayoutOrder = 2,
				Text = "Selected:",
				Font = Enum.Font.BuilderSansBold,
				TextSize = PluginEnum.FontSizeHeader,
				TextColor3 = PluginEnum.ColorTextPrimary,
				BackgroundColor3 = PluginEnum.ColorBackground,
				BorderSizePixel = 0,
				TextXAlignment = Enum.TextXAlignment.Center,
				})
		},
		selectionInstanceWirers, 
		{
			dmWirerHeader = hasDMWires and e("TextLabel", {
			Size = UDim2.new(0, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = dmWirersLabelIndex,
			Text = "Wired to:",
			Font = Enum.Font.BuilderSansBold,
			TextSize = PluginEnum.FontSizeHeader,
			TextColor3 = PluginEnum.ColorTextPrimary,
			BackgroundColor3 = PluginEnum.ColorBackground,
			BorderSizePixel = 0,
			TextXAlignment = Enum.TextXAlignment.Center,
			})
		},
		dmInstanceWirers		
		)
	})
end


function PieceDetailsComponent:renderPreviewAndName(order: number)
	-- print('render piece details component')

	local content = self.props.fetcher:fetch(self.props.piece)
	if self.props.piece.type ~= 'image' then content = nil end

	local image = 'http://www.roblox.com/asset/?id=92229743995007'
	if self.props.piece.type == 'image' then image = nil end 	

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
			Size = UDim2.new(0, PluginEnum.DetailsSize, 0, PluginEnum.DetailsSize),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = PluginEnum.ColorBackground,
			BorderSizePixel = 0,
			ImageContent = content,
			LayoutOrder = 1,
		}),
		imageStaticPreview = image ~= nil and e('ImageLabel', {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = PluginEnum.ColorBackground,
			BorderSizePixel = 0,
			Image= image,
			LayoutOrder = 2,
			Size = UDim2.fromOffset(PluginEnum.PreviewSize, PluginEnum.PreviewSize),
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
			Text = self.props.piece.name,
			Font = Enum.Font.BuilderSansBold,
			TextSize = PluginEnum.FontSizeTextPrimary,
			TextColor3 = PluginEnum.ColorTextPrimary,
			BackgroundColor3 = PluginEnum.ColorBackground,
			BorderSizePixel = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 3
		})
	})
}
end
return PieceDetailsComponent
