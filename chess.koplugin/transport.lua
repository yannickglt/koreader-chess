-- SPDX-License-Identifier: GPL-3.0-or-later
local ffi = require("ffi")
local bit = require("bit")

local has_koreader_posix = pcall(require, "ffi/posix_h")
if has_koreader_posix then
    ffi.cdef[[
    int socketpair(int domain, int type, int protocol, int sv[2]);
    int execv(const char *path, const char *const argv[]);
    ]]
else
ffi.cdef[[
int socketpair(int domain, int type, int protocol, int sv[2]);
int fork(void);
int dup2(int oldfd, int newfd);
int close(int fd);
int execv(const char *path, const char *const argv[]);
void _exit(int status);
long read(int fd, void *buf, size_t count);
long send(int sockfd, const void *buf, size_t len, int flags);
int fcntl(int fd, int cmd, ...);
int kill(int pid, int sig);
int waitpid(int pid, int *status, int options);
int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);
]]
end
ffi.cdef[[ long sysconf(int name); ]]

-- Dans KOReader, le fork passe par ffi/util, qui arrête les threads susceptibles de tenir un
-- verrou malloc avant fork() et exécute les hooks du frontend dans le fils. Hors KOReader
-- (tests sur Mac ou en conteneur nu), fork direct.
local ok_util, ffiUtil = pcall(require, "ffi/util")
local run_in_subprocess = ok_util and type(ffiUtil) == "table" and ffiUtil.runInSubProcess or nil

local C = ffi.C
local O_NONBLOCK = ffi.os == "OSX" and 4 or 2048
local MSG_NOSIGNAL = ffi.os == "OSX" and 0x80000 or 0x4000
local EAGAIN = ffi.os == "OSX" and 35 or 11
local SC_OPEN_MAX = ffi.os == "OSX" and 5 or 4
local Transport = {}
Transport.__index = Transport
Transport.spawner = run_in_subprocess and "koreader" or "fork"

-- Nombre maximal de descripteurs du processus (limite courante), borné pour que la fermeture
-- dans le fils reste brève.
local function max_fds()
    local limit = tonumber(C.sysconf(SC_OPEN_MAX)) or 0
    if limit < 1024 then limit = 1024 end
    if limit > 65536 then limit = 65536 end
    return limit
end

-- Exécuté dans le fils, entre fork et exec : la socket devient stdin/stdout, tous les autres
-- descripteurs hérités de KOReader (écran, tactile, fichiers, réseau) sont fermés.
local function exec_engine(path, argv, sv, limit)
    C.dup2(sv[1], 0)
    C.dup2(sv[1], 1)
    for fd = 3, limit - 1 do C.close(fd) end
    C.execv(path, argv)
    C._exit(127)
end

function Transport.new(path)
    if type(path) ~= "string" or path:sub(1, 1) ~= "/" then return nil, "Chemin du moteur non absolu" end
    local argv = ffi.new("const char *[2]", path, nil)
    local libdir = path:match("^(.*)/[^/]+$")
    local sv = ffi.new("int[2]")
    if C.socketpair(1, 1, 0, sv) ~= 0 then return nil, "socketpair: " .. ffi.errno() end
    -- LD_LIBRARY_PATH est posé dans le parent juste avant le fork et restauré aussitôt après :
    -- le fils hérite de l'environnement sans rien allouer entre fork et exec.
    local previous = os.getenv("LD_LIBRARY_PATH")
    local linux = ffi.os == "Linux"
    local limit = max_fds()
    if linux then C.setenv("LD_LIBRARY_PATH", previous and (libdir .. ":" .. previous) or libdir, 1) end
    local pid, err
    if run_in_subprocess then
        pid, err = run_in_subprocess(function() exec_engine(path, argv, sv, limit) end)
    else
        pid = C.fork()
        if pid == 0 then exec_engine(path, argv, sv, limit) end
    end
    if linux then
        if previous then C.setenv("LD_LIBRARY_PATH", previous, 1) else C.unsetenv("LD_LIBRARY_PATH") end
    end
    C.close(sv[1])
    if not pid or pid < 0 then
        C.close(sv[0])
        return nil, "fork: " .. tostring(err or ffi.errno())
    end
    local flags = C.fcntl(sv[0], 3)
    if flags < 0 or C.fcntl(sv[0], 4, ffi.new("int", bit.bor(flags, O_NONBLOCK))) < 0 then
        C.close(sv[0]); C.kill(pid, 9); C.waitpid(pid, nil, 0)
        return nil, "fcntl: " .. ffi.errno()
    end
    return setmetatable({fd = sv[0], pid = pid, pending = "", buffer = "", closed = false}, Transport)
end

function Transport:send(data)
    if self.closed then return nil, "Moteur arrêté" end
    self.pending = self.pending .. data
    return self:flush()
end

function Transport:flush()
    while #self.pending > 0 do
        local n = tonumber(C.send(self.fd, self.pending, #self.pending, MSG_NOSIGNAL))
        if n < 0 then
            if ffi.errno() == EAGAIN then return true end
            return nil, "Écriture moteur: " .. ffi.errno()
        end
        if n == 0 then return nil, "Moteur fermé" end
        self.pending = self.pending:sub(n + 1)
    end
    return true
end

function Transport:poll()
    if self.closed then return {} end
    local lines = {}
    self:flush()
    local chunk = ffi.new("char[4096]")
    while true do
        local n = tonumber(C.read(self.fd, chunk, 4096))
        if n < 0 then
            if ffi.errno() ~= EAGAIN and ffi.errno() ~= 4 then self.error = "Lecture moteur: " .. ffi.errno() end
            break
        end
        if n == 0 then self.error = "Le moteur s'est arrêté"; break end
        self.buffer = self.buffer .. ffi.string(chunk, n)
        if #self.buffer > 262144 then self.error = "Sortie moteur trop longue"; break end
    end
    while true do
        local stop = self.buffer:find("\n", 1, true)
        if not stop then break end
        lines[#lines + 1] = self.buffer:sub(1, stop - 1):gsub("\r$", "")
        self.buffer = self.buffer:sub(stop + 1)
    end
    return lines
end

function Transport:close()
    if self.closed then return end
    self.closed = true
    C.close(self.fd)
    C.kill(self.pid, 15)
    local status = ffi.new("int[1]")
    if C.waitpid(self.pid, status, 1) == 0 then
        C.kill(self.pid, 9)
        C.waitpid(self.pid, status, 0)
    end
end

return Transport
