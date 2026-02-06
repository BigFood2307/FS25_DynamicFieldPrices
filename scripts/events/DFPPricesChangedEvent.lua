DFPPricesChangedEvent = {}
local DFPPricesChangedEvent_mt = Class(DFPPricesChangedEvent, Event)

InitEventClass(DFPPricesChangedEvent, "DFPPricesChangedEvent")

function DFPPricesChangedEvent:emptyNew()
    local self = Event.new(DFPPricesChangedEvent_mt)

    self.prices = {}

    return self
end

function DFPPricesChangedEvent:new(dfp, prices)
    local self = DFPPricesChangedEvent:emptyNew()

    self.dfp = dfp
    self.prices = prices

    return self
end

function DFPPricesChangedEvent:writeStream(streamId, connection)
    -- [FIX] Count entries explicitly instead of using the # operator.
    --
    -- The prices table is keyed by farmland ID (e.g. prices[fidx] = newPrice).
    -- In Lua 5.1, the # operator on a table with non-sequential integer keys
    -- is *undefined* — it may return any value at a nil/non-nil boundary.
    --
    -- Example: if farmland IDs are {1, 2, 5, 10}, then:
    --   prices = {[1]=p1, [2]=p2, [5]=p5, [10]=p10}
    --   #prices → could return 2, 5, 10, or anything else!
    --
    -- Vanilla FS25 maps use contiguous IDs (1..N) so # works by coincidence,
    -- but custom maps may have gaps. Counting explicitly is always safe.
    local count = 0
    for _ in pairs(self.prices) do
        count = count + 1
    end
    streamWriteInt32(streamId, count)

    -- [FIX] Write farmland ID alongside each price.
    --
    -- Previously, writeStream used pairs() (arbitrary order) to write prices,
    -- but readStream used a sequential for-loop (1, 2, 3, ...) to read them back.
    -- If pairs() happened to iterate in a different order than 1..N, prices would
    -- be assigned to the wrong farmland IDs on the receiving client.
    --
    -- By including the farmland ID with each price, the reader doesn't need to
    -- assume any particular ordering — it maps each price to the correct field by ID.
    for farmlandId, price in pairs(self.prices) do
        streamWriteInt32(streamId, farmlandId)
        streamWriteFloat32(streamId, price)
    end
end

function DFPPricesChangedEvent:readStream(streamId, connection)
    local nPrices = streamReadInt32(streamId)
    for i = 1, nPrices do
        -- [FIX] Read (farmlandId, price) pairs — order-independent.
        local farmlandId = streamReadInt32(streamId)
        local price = streamReadFloat32(streamId)
        self.prices[farmlandId] = price
    end

    self:run(connection)
end

function DFPPricesChangedEvent:run(connection)
    if connection:getIsServer() then
        DynamicFieldPrices:onNewPricesReceived(self.prices)
    end
end