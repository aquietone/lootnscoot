-- Banks all items in your inventory which return Tradeskills=true
-- Note that this probably includes your food if you use autofeed and have water flasks, cheese, bottle of milk, etc.
--- @type Mq
local mq = require('mq')

local function bankItem(itemName)
    mq.cmdf('/nomodkey /shiftkey /itemnotify "%s" leftmouseup', itemName)
    mq.delay(100, function() return mq.TLO.Cursor() end)
    mq.cmd('/notify BigBankWnd BIGB_AutoButton leftmouseup')
    mq.delay(100, function() return not mq.TLO.Cursor() end)
end

if not mq.TLO.Window('BigBankWnd').Open() then
    printf('\arBank window must be open!')
    return
end

for i=1,10 do
    local bagSlot = mq.TLO.InvSlot('pack'..i).Item
    local containerSize = bagSlot.Container()
    if containerSize == 0 then
        if bagSlot.Tradeskills() then bankItem(bagSlot.Name()) end
    else
        for j=1,containerSize do
            if bagSlot.Item(j).Tradeskills() then bankItem(bagSlot.Item(j).Name()) end
        end
    end
end
