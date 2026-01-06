
source(Utils.getFilename("DFPPricesChangedEvent.lua", g_currentModDirectory .. "scripts/events/"))

DynamicFieldPrices = {}

local DynamicFieldPrices_mt = Class(DynamicFieldPrices)

function DynamicFieldPrices.new()
    local self = setmetatable({}, DynamicFieldPrices_mt)

    self.messageCenter = g_messageCenter
    self.farmlandManager = g_farmlandManager
    self.isClient = Mission00:getIsClient()
    self.isServer = Mission00:getIsServer()
    self.name = g_currentModName or "DynamicFieldPrices"
    self.directory = g_currentModDirectory

    self.gui = {}
    self.npcs = {}

    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(MessageType.FARMLAND_OWNER_CHANGED, self.onFarmlandStateChanged, self)

    return self
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
    g_gui:loadProfiles(Utils.getFilename("dfp_profiles.xml", self.directory .. "gui/"))

    self.gui.contextBoxFarmland = g_inGameMenu.pageMapOverview.contextBoxFarmland
    self.gui.contextBoxBg = self.gui.contextBoxFarmland:getFirstDescendant(
        function(e) return e.profile == "fs25_mapContextBoxBgFarmland"
        end )
    self.gui.contextButtons = self.gui.contextBoxFarmland:getDescendantById("contextButtonListFarmland")

    local titles = self.gui.contextBoxFarmland:getDescendants(
        function(e) return e.profile == "fs25_mapContextFarmlandTitle"
        end )

    self.gui.sizeTitle = titles[1]
    self.gui.valueTitle = titles[2]
    self.gui.sizeText = self.gui.contextBoxFarmland:getDescendantByName("farmlandSize")
    self.gui.valueText = self.gui.contextBoxFarmland:getDescendantByName("farmlandValue")

    self.gui.priceChangeTitle = titles[1]:clone(self.gui.contextBoxFarmland)
    self.gui.priceChangeTitle:setText(g_i18n:getText("DFP_PriceChange_Title"))
    self.gui.priceChangeText = self.gui.contextBoxFarmland:getDescendantByName("farmlandSize"):clone(self.gui.contextBoxFarmland)
    self.gui.priceChangeText.name = "farmlandChange"

    self.gui.contextBoxBg:applyProfile("DFP_mapContextBoxBgFarmland")
    self.gui.contextButtons:applyProfile("DFP_mapContextButtonList")

    self.gui.priceChangeTitle:applyProfile("DFP_priceChangeTitle")
    self.gui.priceChangeText:applyProfile("DFP_priceChangeText")

    self.gui.sizeTitle:applyProfile("DFP_sizeTitle")
    self.gui.sizeText:applyProfile("DFP_sizeText")
    self.gui.valueTitle:applyProfile("DFP_valueTitle")
    self.gui.valueText:applyProfile("DFP_valueText")
end

function loadedMap(mapNode, failedReason, arguments, callAsyncCallback, ...)
    g_dynamicFieldPrices:initGui()
end

function startMission(mission)
    g_dynamicFieldPrices:onStartMission(mission)
end

function readStream(e, streamId, connection)
    g_dynamicFieldPrices:onReadStream(streamId, connection)
end

function writeStream(e, streamId, connection)
    g_dynamicFieldPrices:onWriteStream(streamId, connection)
end

function showContextBox(self, clickedLand, ...)
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
            g_dynamicFieldPrices.gui.priceChangeText:setText(difference)
        else
            g_dynamicFieldPrices.gui.priceChangeText:setText("hidden")
        end
    end
end

addModEventListener(DynamicFieldPrices)

g_dynamicFieldPrices = DynamicFieldPrices.new()

InGameMenuMapUtil.showContextBox = Utils.appendedFunction(InGameMenuMapUtil.showContextBox, showContextBox)
BaseMission.loadMapFinished = Utils.appendedFunction(BaseMission.loadMapFinished, loadedMap)
Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, startMission)
SavegameSettingsEvent.readStream = Utils.appendedFunction(SavegameSettingsEvent.readStream, readStream)
SavegameSettingsEvent.writeStream = Utils.appendedFunction(SavegameSettingsEvent.writeStream, writeStream)

