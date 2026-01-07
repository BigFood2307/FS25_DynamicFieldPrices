
DFPSettings = {}
DFPSettings.name = g_currentModName
DFPSettings.modDir = g_currentModDirectory

DFPSettings.debug = false

source(g_currentModDirectory .. "scripts/events/changeDFPCheckSettingsEvent.lua")
source(g_currentModDirectory .. "scripts/events/changeDFPDecimalSettingsEvent.lua")
source(g_currentModDirectory .. "scripts/events/loadDFPSettingsEvent.lua")

function DFPSettings.init()
    -- init default settings
    DFPSettings.current = {}
    DFPSettings.current.MinGreed = 0.8
    DFPSettings.current.MaxGreed = 1.2
    DFPSettings.current.MinEco = 0.6
    DFPSettings.current.MaxEco = 1.6
    DFPSettings.current.Discourage = 0.1
    DFPSettings.current.ResetNPCs = false
    DFPSettings.current.ShowPriceModifier = true

    DFPSettings.lowests = {}
    DFPSettings.steps = {}

--     -- listen zum speichern der elemente für das wieder füllen bei änderungen von anderen
--     DFPSettings.checkElements = {}
--     DFPSettings.textElements = {}

    -- Einstellungen speichern und laden
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, DFPSettings.loadSettingsXML)
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, DFPSettings.saveSettingsXML)

    InGameMenuSettingsFrame.updateGameSettings = Utils.appendedFunction(InGameMenuSettingsFrame.updateGameSettings, DFPSettings.updateGameSettings)

    -- damit beim joinen im MP die einstellungen geholt werden senden wir ein event dass die einstellungen dann an alle schickt
    FSBaseMission.onConnectionFinishedLoading = Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, DFPSettings.loadSettingsFromServer)

    DFPSettings:extendSettingsScreen()
end

function DFPSettings:extendSettingsScreen()

    local settingsPage = g_inGameMenu.pageSettings
    local scrollPanel = settingsPage.gameSettingsLayout

    for _, element in pairs(scrollPanel.elements) do
        if element.name == "sectionHeader" then
            self.sectionHeader = element:clone(scrollPanel)
        end

        if element.typeName == "Bitmap" then
            if element.elements[1].typeName == "BinaryOption" then
                self.binaryOptionElement = element
            end
        end

        if element.typeName == "Bitmap" then
            if element.elements[1].typeName == "MultiTextOption" then
                self.multiTextOption = element
            end
        end

        if self.sectionHeader ~= nil and self.binaryOptionElement ~= nil and self.multiTextOption ~= nil then
            break
        end
    end

    self.sectionHeader:setText(g_i18n:getText("DFP_Settings_Title"))

    DFPSettings:addPercentageSettingsOption(scrollPanel, settingsPage, "MinGreed", 0.5, 1.25, 0.05)
    DFPSettings:addPercentageSettingsOption(scrollPanel, settingsPage, "MaxGreed", 0.75, 2.0, 0.05)
    DFPSettings:addPercentageSettingsOption(scrollPanel, settingsPage, "MinEco", 0.25, 1.0, 0.05)
    DFPSettings:addPercentageSettingsOption(scrollPanel, settingsPage, "MaxEco", 1.0, 3.0, 0.05)
    DFPSettings:addPercentageSettingsOption(scrollPanel, settingsPage, "Discourage", 0, 0.25, 0.025)
    DFPSettings:addBinarySettingsOption(scrollPanel, settingsPage, "ResetNPCs")
    DFPSettings:addBinarySettingsOption(scrollPanel, settingsPage, "ShowPriceModifier")

    scrollPanel:invalidateLayout()
end

function DFPSettings:addBinarySettingsOption(scrollPanel, settingsPage, settingName)
    function updateSetting(_, state)
        g_client:getServerConnection():sendEvent(ChangeDFPCheckSettingsEvent.new(settingName, state == 2))
    end

    local parent = self.binaryOptionElement:clone(scrollPanel)
    local newOption = parent.elements[1]
    parent.id = nil

    parent.elements[2]:setText(g_i18n:getText("DFP_" .. settingName .. "_Title"))

    newOption.elements[1]:setText(g_i18n:getText("DFP_" .. settingName .. "_Tooltip"))
    newOption.id = "DFP_" .. settingName .. "_Id"
    newOption.onClickCallback = updateSetting
    settingsPage["DFP_" .. settingName] = newOption

    parent:setVisible(true)
    parent:setDisabled(false)
end

function DFPSettings:addPercentageSettingsOption(scrollPanel, settingsPage, settingName, lowest, highest, step)
    function updateSetting(_, state)
        g_client:getServerConnection():sendEvent(ChangeDFPDecimalSettingsEvent.new(settingName, lowest + (state-1)*step))
    end

    local parent = self.multiTextOption:clone(scrollPanel)
    local newOption = parent.elements[1]
    parent.id = nil

    parent.elements[2]:setText(g_i18n:getText("DFP_" .. settingName .. "_Title"))

    newOption.elements[1]:setText(g_i18n:getText("DFP_" .. settingName .. "_Tooltip"))
    newOption.id = "DFP_" .. settingName .. "_Id"
    self.lowests[settingName] = lowest
    self.steps[settingName] = step
    newOption.onClickCallback = updateSetting
    settingsPage["DFP_" .. settingName] = newOption

    local texts = table.create((highest - lowest) // step)
    for i=lowest,highest,step do
        table.insert(texts, string.format("%.1f%%", i*100))
    end

    newOption:setTexts(texts)

    parent:setVisible(true)
    parent:setDisabled(false)
end

function DFPSettings.updateGameSettings()
    for k, v in pairs(DFPSettings.current) do
        if type(v) == "boolean" then
            local state = 1
            if v then
                state = 2
            end
            g_inGameMenu.pageSettings["DFP_" .. k]:setState(state)
        end
        if type(v) == "number" and DFPSettings.lowests[k] ~= nil then
            local state = math.round((v-DFPSettings.lowests[k])/DFPSettings.steps[k])
            g_inGameMenu.pageSettings["DFP_" .. k]:setState(state+1)
        end
    end
end

function DFPSettings:getText(key)
    local result = g_i18n.modEnvironments[DFPSettings.name].texts[key]
    if result == nil then
        return g_i18n:getText(key)
    end
    return result
end

function DFPSettings.saveSettingsXML(missionInfo)
    if(DFPSettings.current == nil) then
        return
    end

    local xmlFile = XMLFile.create("DynamicFieldPricesXML", missionInfo.savegameDirectory .. "/dynamicFieldPrices.xml", "dynamicFieldPrices")
    if xmlFile ~= nil then
        xmlFile:setInt("dynamicFieldPrices#version", 1)

        xmlFile:setFloat("dynamicFieldPrices.greediness#min", DFPSettings.current.MinGreed)
        xmlFile:setFloat("dynamicFieldPrices.greediness#max", DFPSettings.current.MaxGreed)
        xmlFile:setFloat("dynamicFieldPrices.economicSit#min", DFPSettings.current.MinEco)
        xmlFile:setFloat("dynamicFieldPrices.economicSit#max", DFPSettings.current.MaxEco)
        xmlFile:setFloat("dynamicFieldPrices.discourage#value", DFPSettings.current.Discourage)
        xmlFile:setBool("dynamicFieldPrices.priceModifier", DFPSettings.current.ShowPriceModifier)

        DynamicFieldPrices:onMissionSaveToSavegame(xmlFile)

        xmlFile:save()
    end
end

function DFPSettings.loadSettingsXML(mission, node)
    if mission:getIsServer() then
        if mission.missionInfo.savegameDirectory ~= nil and fileExists(mission.missionInfo.savegameDirectory .. "/dynamicFieldPrices.xml") then
            local xmlFile = XMLFile.load("DynamicFieldPricesXML", mission.missionInfo.savegameDirectory .. "/dynamicFieldPrices.xml")
            if xmlFile ~= nil then
                local version = xmlFile:getInt("dynamicFieldPrices#version")

                DFPSettings.loadSettingsFloat(xmlFile, "greediness#min", "MinGreed")
                DFPSettings.loadSettingsFloat(xmlFile, "greediness#max", "MaxGreed")
                DFPSettings.loadSettingsFloat(xmlFile, "economicSit#min", "MinEco")
                DFPSettings.loadSettingsFloat(xmlFile, "economicSit#max", "MaxEco")
                DFPSettings.loadSettingsFloat(xmlFile, "discourage#value", "Discourage")
                DFPSettings.loadSettingsBool(xmlFile, "priceModifier", "ShowPriceModifier")

                DynamicFieldPrices:onMissionLoadFromSavegame(xmlFile, version)

                xmlFile:delete()
            end
        end
    end
end

function DFPSettings.loadSettingsFloat(xmlFile, xmlKey, settingsId)
    local value = xmlFile:getFloat("dynamicFieldPrices." .. xmlKey)
    if value == nil then
        return
    end
    DFPSettings.current[settingsId] = value
    DFPSettings:print("Dynamic Field Prices: Loaded '" .. settingsId .. "': " .. tostring(DFPSettings.current[settingsId]))
end

function DFPSettings.loadSettingsBool(xmlFile, xmlKey, settingsId)
    local value = xmlFile:getBool("dynamicFieldPrices." .. xmlKey)
    if value == nil then
        return
    end
    DFPSettings.current[settingsId] = value
    DFPSettings:print("Dynamic Field Prices: Loaded '" .. settingsId .. "': " .. tostring(DFPSettings.current[settingsId]))
end

function DFPSettings.loadSettingsFromServer()
    DFPSettings:print("Dynamic Field Prices: Request settings from server")
    g_client:getServerConnection():sendEvent(LoadDFPSettingsEvent.new())
end

function DFPSettings:print(text)
    if DFPSettings.debug then
        print(text)
    end
end

function DFPSettings:getRatio(key, value)
    local maxVal = DFPSettings.current["Max"..key]
    local minVal = DFPSettings.current["Min"..key]

    if maxVal == nil or minVal == nil then
        return 1
    end

    local range = maxVal - minVal

    return (value - minVal) / range
end

function DFPSettings:getValue(key, ratio)
    local maxVal = DFPSettings.current["Max"..key]
    local minVal = DFPSettings.current["Min"..key]

    if maxVal == nil or minVal == nil then
        return 1
    end

    local range = maxVal - minVal

    return minVal + (ratio * range)
end

function DFPSettings:getDiscourage()
    if DFPSettings.current.Discourage == nil then
        return 0.1
    end
    return DFPSettings.current.Discourage
end

DFPSettings.init()