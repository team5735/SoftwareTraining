-- see https://www.lua.org/manual/5.4/manual.html
-- should work with 5.5 but 5.4 is what i'm writing against
require("os")
local inspect = require("inspect")

local function sh(cmd, perline)
    local handle = assert(io.popen(cmd))
    local stdout
    if perline then
        stdout = {}
        for line in handle:lines() do table.insert(stdout, line) end
    else
        stdout = handle:read("*a")
    end
    return stdout, handle:close()
end

local function printf(fmt, ...) io.write(string.format(fmt .. "\n", ...)) end

local function yesno(query)
    io.write(query .. " (y/n)? ")
    local response = io.read("*l")
    return response:lower() == "y"
end

local function map(tbl, fn)
    local res = {}
    for i, v in ipairs(tbl) do table.insert(res, fn(v)) end
    return res
end

local function join(str, tbl)
    local res = ""
    for _, v in ipairs(tbl) do res = res .. tbl .. str end
    res = res:sub(1, - #res)
    return res
end

local handlers = {}

local function try_guess_name()
    -- expected format: firstname_lastname
    local username = os.getenv("USER")
    if not username then return end
    local underscore = username:find("_")
    if not underscore then return end
    return username:sub(1, underscore - 1):lower(), username:sub(underscore + 1):lower()
end

local function upperone(s) return s:sub(1, 1):upper() .. s:sub(2) end

function handlers.setup_git()
    local firstname, lastname = try_guess_name()
    while true do
        if firstname and lastname then
            printf("user.name: %s %s", upperone(firstname), upperone(lastname))
            printf("user.email: %s_%s@student.waylandps.org", firstname, lastname)
            local correct = yesno("is this correct")
            if correct then break end
        end

        io.write("first name: ")
        firstname = io.read("*l")
        io.write("last name: ")
        lastname = io.read("*l")
    end
end

local function get_have()
    if _G.have then return _G.have end
    local have = {}
    local installed = sh("dpkg-query --show --showformat '${Package}\n'", true)
    for _, pkg in pairs(installed) do have[pkg] = true end
    _G.have = have
    return have
end

function handlers.pkgs(requested)
    if requested == true then requested = nil end
    requested = requested or
        { "wget", "pv", "pigz", "tar", "git", "gh", "libicu-dev", "libnspr4", "libnss3", "clang-format" }

    local to_install = {}
    for _, pkg in pairs(requested) do
        if not get_have()[pkg] then table.insert(to_install, pkg) end
    end
    if not next(to_install) then return end

    printf("installing %d packages", #to_install)
    os.execute("sudo apt-get update")
    os.execute("sudo apt-get install " .. join(" ", to_install))
    for _, v in pairs(to_install) do _G.have[v] = true end
end

local options = {}
for i = 1, #arg, 2 do options[arg[i]] = arg[i + 1] end
for k, v in pairs(options) do if v == "true" then options[k] = true end end
if #arg % 2 == 1 then options["wpilib"] = arg[#arg] end
if not next(options) then
    -- no given options, standard install
    -- will call handlers.setup_git(true), handlers.pkgs(true), etc
    options = {
        setup_git = true,
        pkgs = true,
        gh = true,
        clone = "~/FRC",
        prepush = true,
        wpilib = true,
    }
end

for opt_name, value in pairs(options) do handlers[opt_name](value) end
