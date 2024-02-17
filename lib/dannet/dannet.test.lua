local mq = require('mq')
local Write = require('lib/Write')
local dannet = require('lib/dannet/helpers')

local args = {...}
local peer = args[1]

if peer == nil then 
  Write.Error('\arNeed a peer name to run dannet.test')
  return 
end

Write.loglevel = 'debug'
Write.usecolors = false
Write.prefix = function() return string.format('\aw[%s] [\a-tDanNet Test\aw]\at ', mq.TLO.Time()) end

local i = 0
while true do  

  if i < 10 then
    dannet.observe(peer, 'Me.Moving')
    dannet.query(peer, 'Me.FreeInventory')
  else
    dannet.unobserve(peer, 'Me.Moving')
    mq.exit()
  end

  i = i + 1
  mq.delay('1s')
end