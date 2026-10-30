package.path = "chess.koplugin/?.lua;" .. package.path
local Transport = require("transport")

local io = assert(Transport.new("/bin/cat"))
assert(#io:poll() == 0)
assert(io:send("hello\n"))
local got
for _ = 1, 100 do
    local lines = io:poll()
    if lines[1] then got = lines[1]; break end
    os.execute("sleep 0.01")
end
assert(got == "hello", tostring(got))
io:close()
assert(io.closed)
print("transport: OK")
