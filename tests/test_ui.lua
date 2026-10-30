package.path = "chess.koplugin/?.lua;" .. package.path
local shown = {}
local settings = {data = {}}
function settings:readSetting(key) return self.data[key] end
function settings:saveSetting(key, value) self.data[key] = value end
function settings:flush() end

package.preload["ffi/blitbuffer"] = function() return {COLOR_WHITE = 1, COLOR_LIGHT_GRAY = 2} end
package.preload["ui/widget/buttondialog"] = function() return {new = function(_, args)
    local buttons = {}
    for _, row in ipairs(args.buttons) do
        for _, entry in ipairs(row) do
            if entry.id then
                buttons[entry.id] = {
                    text = entry.text, width = 100,
                    setText = function(self, value) self.text = value end,
                    refresh = function() end,
                }
            end
        end
    end
    args.buttontable = {getButtonById = function(_, id) return buttons[id] end}
    return args
end} end
package.preload["ui/widget/confirmbox"] = function() return {new = function(_, args) return args end} end
package.preload["datastorage"] = function() return {getSettingsDir = function() return "/tmp" end} end
package.preload["ui/widget/infomessage"] = function() return {new = function(_, args) return args end} end
package.preload["luasettings"] = function() return {open = function() return settings end} end
package.preload["ui/uimanager"] = function() return {
    show = function(_, dialog) shown[#shown + 1] = dialog end,
    close = function() end, unschedule = function() end, scheduleIn = function() end,
} end
package.preload["ui/widget/container/widgetcontainer"] = function() return {
    extend = function(_, values) values.__index = values; return values end,
} end
package.preload["ffi/util"] = function() return {} end

local Chess = dofile("chess.koplugin/main.lua")
local registered
local chess = setmetatable({ui = {menu = {registerToMainMenu = function(_, plugin) registered = plugin end}}}, Chess)
chess:init()
assert(registered == chess)
local menu = {}
chess:addToMainMenu(menu)
assert(menu.chess.text == "Échecs")
chess.startEngine = function() return true end
chess:openBoard()
chess.game:update("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", {"e2e4"}, false)
chess.waiting = false
chess:render()
local played
chess.engine = {play = function(_, moves) played = moves[#moves] end}
chess:tapSquare("e2")
assert(chess.selected == "e2")
assert(chess.dialog.buttontable:getButtonById("e2").text == "•♙")
chess:tapSquare("e4")
assert(played == "e2e4")
assert(chess.selected == nil)
assert(settings.data.game.moves[1] == "e2e4")
local searches = 0
chess.engine = {send = function(_, command) if command == "go movetime 150" then searches = searches + 1 end end}
local should_search = chess:acceptPosition("4k3/7p/8/8/8/8/P7/4K3 b - - 100 51", {"e8e7"}, false)
assert(should_search == false and chess.pending_draw_decision and searches == 0)
chess:continueAfterClaim()
assert(searches == 1 and chess.waiting and not chess.pending_draw_decision)
chess:claimDraw()
assert(chess.game:result() == "nulle_reclamee" and not chess.waiting)
local stopped = false
chess.transport = {close = function() stopped = true end}
chess:onSuspend()
assert(stopped and chess.transport == nil and chess.engine == nil and chess.waiting)
chess:closeBoard()
print("ui: OK")
