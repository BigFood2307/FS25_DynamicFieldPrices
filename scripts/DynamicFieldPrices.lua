
source(Utils.getFilename("DFPPricesChangedEvent.lua", g_currentModDirectory .. "scripts/events/"))

DynamicFieldPrices = {}

function DynamicFieldPrices:init()

    self.messageCenter = g_messageCenter
    self.farmlandManager = g_farmlandManager
    self.isClient = Mission00:getIsClient()
    self.isServer = Mission00:getIsServer()
    self.name = g_currentModName or "FS25_DynamicFieldPrices"
    self.directory = g_currentModDirectory

    self.gui = {}
    self.npcs = {}

    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(MessageType.FARMLAND_OWNER_CHANGED, self.onFarmlandStateChanged, self)
end

function DynamicFieldPrices:delete()
    self.messageCenter:unsubscribeAll(self)
    self.farmlandManager:removeStateChangeListener(self)
end

function DynamicFieldPrices:onWriteStream(streamId, connection)
    fls = self.farmlandManager.farmlands
    for fidx, field in pairs(fls) do
        streamWriteFloat32(streamId, field.price)
    end
end

function DynamicFieldPrices:onReadStream(streamId, connection)
    fls = self.farmlandManager.farmlands
    for fidx, field in pairs(fls) do
        field.price = streamReadFloat32(streamId)
    end
end

function DynamicFieldPrices:onNewPricesReceived(prices)
    if not self.isServer then
        local fls = self.farmlandManager.farmlands
        for fidx, field in pairs(fls) do
            field.price = prices[fidx]
        end	
    end
end

function DynamicFieldPrices:calcPrice()
    local pph = self.farmlandManager.pricePerHa
    local fls = self.farmlandManager.farmlands
    local prices = {}
    for fidx, field in pairs(fls) do
        local newPrice = 0
        if field.fixedPrice ~= nil then
            newPrice = field.fixedPrice
        else
            newPrice = field.areaInHa * pph * field.priceFactor
        end
        local npcIdx = field.npcIndex
        if self.npcs[npcIdx] == nil then
            self:createRandomNPC(npcIdx)
        end
        newPrice = newPrice * DFPSettings:getValue("Greed", self.npcs[npcIdx].greediness)
        newPrice = newPrice * DFPSettings:getValue("Eco", self.npcs[npcIdx].economicSit)
        local sellFactor = 1
        if field.isOwned then
            sellFactor = sellFactor - DFPSettings:getDiscourage()
        else
            sellFactor = sellFactor + DFPSettings:getDiscourage()
        end
        newPrice = newPrice*sellFactor
        field.price = newPrice
        prices[fidx] = newPrice
    end

    g_server:broadcastEvent(DFPPricesChangedEvent:new(self, prices))
end

function DynamicFieldPrices:createRandomNPC(i)
    local npc = {
        greediness = math.random(),
        economicSit = math.random()
    }
    self.npcs[i] = npc
end

function DynamicFieldPrices:randomizeNPCs()
    for nidx, fnpc in pairs(self.npcs) do
        fnpc.economicSit = fnpc.economicSit + (math.random()-0.5)*0.2
        fnpc.economicSit = math.max(math.min(fnpc.economicSit, 1), 0)
    end
end

function DynamicFieldPrices:onDayChanged(day)
    print("Day passed!")
    if self.isServer then
        if DFPSettings.current.ResetNPCs then
            self.npcs = {}

            DFPSettings.current.ResetNPCs = false
            g_server:broadcastEvent(ChangeDFPCheckSettingsEvent.new("ResetNPCs", false), false)
        end
        self:randomizeNPCs()
        self:calcPrice()
    end
end

function DynamicFieldPrices:onSettingsChanged()
    if self.isServer then
        self:calcPrice()
    end
end

function DynamicFieldPrices:onFarmlandStateChanged(farmlandId, farmId)
    if self.isServer then
        self:calcPrice()
    end
end

function DynamicFieldPrices:onStartMission(mission)
    if self.isServer then
        self:calcPrice()
    end
    self:guiCompatibility()
end

function DynamicFieldPrices:onMissionSaveToSavegame(xmlFile)

    if self.npcs ~= nil then
        for i, snpc in pairs(self.npcs) do
            local key = ("dynamicFieldPrices.npcs.npc(%d)"):format(i - 1)

            xmlFile:setInt(key .. "#id", i)
            xmlFile:setFloat(key .. "#greediness",snpc.greediness)
            xmlFile:setFloat(key .. "#economicSit",snpc.economicSit)
        end
    end
end

function DynamicFieldPrices:onMissionLoadFromSavegame(xmlFile, xmlVersion)

    xmlFile:iterate("dynamicFieldPrices.npcs.npc", function(_, key)
        local npc = {}
        local id = xmlFile:getInt(key .. "#id")
        if id ~= nil then
            npc.greediness = xmlFile:getFloat(key .. "#greediness")
            npc.economicSit = xmlFile:getFloat(key .. "#economicSit")

            self.npcs[id] = npc
        end
    end)
end

function DynamicFieldPrices:initGui()
    local xmlFile = loadXMLFile("Temp", Utils.getFilename("dfp_gui.xml", self.directory .. "gui/"))
    self.mapFrame = g_inGameMenu.pageMapOverview

    local contextBox = self.mapFrame.contextBoxFarmland
    local background = contextBox.elements[1]

    g_gui:loadProfileSet(xmlFile, "GUI.GuiProfiles", g_gui.profiles)
    g_gui:loadGuiRec(xmlFile, "GUI", contextBox, self.mapFrame)

    self.contextBoxExtension = contextBox.elements[#contextBox.elements]
    self.priceChangeValueElement = self.contextBoxExtension.elements[3]

    local farmlandBoxHeight = contextBox.size[2]
    local farmlandBoxBgHeight = background.size[2]

    contextBox:setSize(nil, farmlandBoxHeight + self.contextBoxExtension.size[2])
    background:setSize(nil, farmlandBoxBgHeight + self.contextBoxExtension.size[2])
end

function DynamicFieldPrices:guiCompatibility()
    if g_modIsLoaded["FS25_precisionFarming"] then

        -- anchor deltas are only recalculated, if they are first deleted. Is there a better solution?
        self.mapFrame.fieldBuyInfoWindow.anchorDeltas = {}
        self.mapFrame.fieldBuyInfoWindow:move(0, -self.contextBoxExtension.size[2])
    end
end

function DynamicFieldPrices:loadMap(i3dName)
    DynamicFieldPrices:initGui()
    Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, DynamicFieldPrices.startMission)
    InGameMenuMapUtil.showContextBox = Utils.appendedFunction(InGameMenuMapUtil.showContextBox, DynamicFieldPrices.showContextBox)
    SavegameSettingsEvent.readStream = Utils.appendedFunction(SavegameSettingsEvent.readStream, DynamicFieldPrices.readStream)
    SavegameSettingsEvent.writeStream = Utils.appendedFunction(SavegameSettingsEvent.writeStream, DynamicFieldPrices.writeStream)
end

function DynamicFieldPrices.startMission(mission)
    DynamicFieldPrices:onStartMission(mission)
end

function DynamicFieldPrices.readStream(e, streamId, connection)
    DynamicFieldPrices:onReadStream(streamId, connection)
end

function DynamicFieldPrices.writeStream(e, streamId, connection)
    DynamicFieldPrices:onWriteStream(streamId, connection)
end

function DynamicFieldPrices.showContextBox(self, clickedLand, ...)
    if self.id == "contextBoxFarmland" then
        local farmland = clickedLand.farmland
        print("Farmland " .. clickedLand.farmland.name .. "!")
        local farmlandValueElement = self:getDescendantByName("farmlandValue")
        print(farmlandValueElement:getText())

        local baseprice = farmland.areaInHa*g_farmlandManager.pricePerHa*farmland.priceFactor
        local mult = 1
        local bcFactor = 1
        local finalPrice = farmland.price*bcFactor
        if baseprice ~= 0 then
            mult = finalPrice/baseprice
        end		
        local difference = string.format("%.1f %%", (mult-1)*100)
        if mult >= 1 then
            difference = "+" .. difference
        end

        if DFPSettings.current.ShowPriceModifier then
            DynamicFieldPrices.priceChangeValueElement:setText(difference)
        else
            DynamicFieldPrices.priceChangeValueElement:setText("hidden")
        end
    end
end

addModEventListener(DynamicFieldPrices)

DynamicFieldPrices:init()

