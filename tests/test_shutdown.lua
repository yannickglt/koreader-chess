package.path = "chess.koplugin/?.lua;" .. package.path
local ffi = require("ffi")
local Transport = require("transport")
local binary = assert(os.getenv("STOCKFISH"))
local transport = assert(Transport.new(binary))
local pid = transport.pid
assert(transport:send("uci\ngo infinite\n"))
for _ = 1, 20 do transport:poll(); os.execute("sleep 0.01") end
transport:close()
assert(transport.closed)
assert(ffi.C.kill(pid, 0) == -1)
print("shutdown: OK")
