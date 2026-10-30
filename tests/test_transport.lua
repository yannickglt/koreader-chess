package.path = "chess.koplugin/?.lua;" .. package.path
local ffi = require("ffi")
local Transport = require("transport")

local function read_all(io, deadline)
    local got = {}
    for _ = 1, deadline or 200 do
        for _, line in ipairs(io:poll()) do got[#got + 1] = line end
        if io.error then break end
        os.execute("sleep 0.01")
    end
    return got
end

local cat = assert(Transport.new("/bin/cat"))
assert(#cat:poll() == 0)
assert(cat:send("hello\n"))
local got
for _ = 1, 100 do
    local lines = cat:poll()
    if lines[1] then got = lines[1]; break end
    os.execute("sleep 0.01")
end
assert(got == "hello", tostring(got))
cat:close()
assert(cat.closed)
assert(ffi.C.kill(cat.pid, 0) == -1) -- processus terminé et récolté

-- Les descripteurs ouverts dans le parent ne sont pas hérités par le moteur : le script fils
-- tente d'écrire sur le n° 50 et sur le plus haut descripteur autorisé, et doit échouer.
ffi.cdef[[
int socketpair(int domain, int type, int protocol, int sv[2]);
int dup2(int oldfd, int newfd);
long sysconf(int name);
int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);
]]
local extra = ffi.new("int[2]")
assert(ffi.C.socketpair(1, 1, 0, extra) == 0)
assert(ffi.C.dup2(extra[0], 50) == 50)
local high = tonumber(ffi.C.sysconf(ffi.os == "OSX" and 5 or 4)) - 1
if high > 65535 then high = 65535 end
assert(ffi.C.dup2(extra[0], high) == high, "dup2 vers le descripteur " .. high)
local function probe(fd)
    local script = os.tmpname()
    local file = assert(io.open(script, "w"))
    file:write("#!/bin/sh\nif (echo x >&" .. fd .. ") 2>/dev/null; then echo INHERITED; else echo CLEAN; fi\n")
    file:close()
    os.execute("chmod +x " .. script)
    local child = assert(Transport.new(script))
    local lines = read_all(child)
    child:close()
    os.remove(script)
    assert(lines[1] == "CLEAN", "descripteur " .. fd .. " hérité par le fils: " .. tostring(lines[1]))
end
probe(50)
probe(high)

-- LD_LIBRARY_PATH est restauré dans le parent après le lancement (posé ou absent au départ).
assert(ffi.C.setenv("LD_LIBRARY_PATH", "/sentinelle", 1) == 0)
local child = assert(Transport.new("/bin/cat")); child:close()
assert(os.getenv("LD_LIBRARY_PATH") == "/sentinelle", tostring(os.getenv("LD_LIBRARY_PATH")))
assert(ffi.C.unsetenv("LD_LIBRARY_PATH") == 0)
child = assert(Transport.new("/bin/cat")); child:close()
assert(os.getenv("LD_LIBRARY_PATH") == nil, tostring(os.getenv("LD_LIBRARY_PATH")))
print("transport: OK (" .. Transport.spawner .. ")")
