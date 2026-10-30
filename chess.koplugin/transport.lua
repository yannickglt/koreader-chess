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
]]
end

local C = ffi.C
local O_NONBLOCK = ffi.os == "OSX" and 4 or 2048
local MSG_NOSIGNAL = ffi.os == "OSX" and 0x80000 or 0x4000
local EAGAIN = ffi.os == "OSX" and 35 or 11
local Transport = {}
Transport.__index = Transport

function Transport.new(path)
    if type(path) ~= "string" or path:sub(1, 1) ~= "/" then return nil, "Chemin du moteur non absolu" end
    local argv = ffi.new("const char *[2]", path, nil)
    local libdir = path:match("^(.*)/[^/]+$")
    local ld_path = libdir .. ":" .. (os.getenv("LD_LIBRARY_PATH") or "")
    local sv = ffi.new("int[2]")
    if C.socketpair(1, 1, 0, sv) ~= 0 then return nil, "socketpair: " .. ffi.errno() end
    local pid = C.fork()
    if pid < 0 then
        C.close(sv[0]); C.close(sv[1])
        return nil, "fork: " .. ffi.errno()
    end
    if pid == 0 then
        C.close(sv[0])
        C.dup2(sv[1], 0)
        C.dup2(sv[1], 1)
        C.close(sv[1])
        if ffi.os == "Linux" then
            C.setenv("LD_LIBRARY_PATH", ld_path, 1)
        end
        C.execv(path, argv)
        C._exit(127)
    end
    C.close(sv[1])
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
