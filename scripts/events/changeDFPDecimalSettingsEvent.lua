--[[
Originally Part of Production Revamp

Copyright (C) braeven & Achimobil 2022

Author: Achimobil, adjusted with permission by BigFood
]]

ChangeDFPDecimalSettingsEvent = {}
ChangeDFPDecimalSettingsEvent_mt = Class(ChangeDFPDecimalSettingsEvent, Event);
InitEventClass(ChangeDFPDecimalSettingsEvent, "ChangeDFPDecimalSettingsEvent");

---Create instance of Event class
function ChangeDFPDecimalSettingsEvent.emptyNew()
    local self = Event.new(ChangeDFPDecimalSettingsEvent_mt);
    return self;
end

---Create new instance of event
function ChangeDFPDecimalSettingsEvent.new(settingsId, newValue)
    DFPSettings:print("ChangeDFPDecimalSettingsEvent.new");
    local self = ChangeDFPDecimalSettingsEvent.emptyNew();
    self.settingsId = settingsId;
    self.newValue = newValue;
    return self;
end

---Called on client side on join
-- @param integer streamId streamId
-- @param integer connection connection
function ChangeDFPDecimalSettingsEvent:readStream(streamId, connection)
    DFPSettings:print("ChangeDFPDecimalSettingsEvent.readStream");
    self.settingsId = streamReadString(streamId);
    self.newValue = streamReadFloat32(streamId)

    self:run(connection)
end

---Called on server side on join
-- @param integer streamId streamId
-- @param integer connection connection
function ChangeDFPDecimalSettingsEvent:writeStream(streamId, connection)
    DFPSettings:print("ChangeDFPDecimalSettingsEvent.writeStream");
    streamWriteString(streamId, self.settingsId)
    streamWriteFloat32(streamId, self.newValue)
end

---Run action on receiving side
-- @param integer connection connection
function ChangeDFPDecimalSettingsEvent:run(connection)
    DFPSettings:print("ChangeDFPDecimalSettingsEvent.run");
    DFPSettings.current[self.settingsId] = self.newValue;

    -- [FIX] Only recalculate and broadcast on the server.
    --
    -- Previously, calcPrice() was called unconditionally — on both server AND clients.
    -- The problem: calcPrice() ends with g_server:broadcastEvent(...), but g_server
    -- is nil on clients. This causes a Lua nil-reference error on every client whenever
    -- ANY player changes a decimal setting (MinGreed, MaxGreed, MinEco, MaxEco, Discourage).
    --
    -- The server already handles everything clients need:
    --   1. calcPrice() recalculates all field prices on the server
    --   2. calcPrice() broadcasts DFPPricesChangedEvent to all clients (new prices)
    --   3. broadcastEvent(self) forwards this settings change to other clients
    --
    -- So clients only need to update their local DFPSettings.current (done above).
    -- They'll receive the updated prices via DFPPricesChangedEvent automatically.
    --
    -- This now matches the pattern used by ChangeDFPCheckSettingsEvent:run(), which
    -- correctly keeps its broadcast inside the g_server guard without calling calcPrice().
    if g_server ~= nil then
        DynamicFieldPrices:calcPrice()
        g_server:broadcastEvent(self, false)
    end
end
