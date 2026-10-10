-- if you want to learn some of either bash or lua, setup.sh and setup.lua
-- mostly do the same things

-- lua reference: https://www.lua.org/manual/5.4/manual.html
-- should work with 5.5 but 5.4 is what i'm writing against
local os = require("os")

----- begin lua implementation of getopt_long(3) -----

---@param opts option[]
local function stderr_options(opts)
    io.stderr:write("options:\n")
    local longest_long = 0
    for _, v in pairs(opts) do if #v.long > longest_long then longest_long = #v.long end end
    for _, v in pairs(opts) do
        io.stderr:write(string.format("-%s --%-" .. longest_long .. "s  arg: %s\n", v.short or " ", v.long, v.arg))
    end
end

---@param opts option[]
---@param msg string
---@param exit_status number?
local function option_error(opts, msg, exit_status)
    io.stderr:write(msg .. "\n")
    stderr_options(opts)
    os.exit(exit_status or 1)
end

---@param opts option[]
---@param optname string
local function miss_arg(opts, optname) option_error(opts, "miss required arg for " .. optname) end

---@class option
---@field short string? short form
---@field long string long form
---@field arg argness takes no option if nil
---@alias argness "none" | "optional" | "required"

---@param opts option[]
---@param optname string
---@return option
local function find_opt(opts, optname)
    local found
    for _, opt in pairs(opts) do
        if opt.short == optname or opt.long == optname then
            found = opt
            break
        end
    end
    if not found then option_error(opts, "unknown opt: " .. optname) end
    return found
end

---@param opts option[] options
-- returns { opt.long = opt } for all found opts, and then string[] nonoptions
local function getopt(opts)
    local i = 1
    local count = 1
    local parsed = {}
    local nonoptions = {} ---@type string[]

    while i <= #arg do
        local a = arg[i]

        if a == "--" then
            i = i + 1
            break
        elseif a == "-" then
            break
        elseif a:sub(1, 2) == "--" then
            local pos = a:find("=", 1, true)

            local optname
            local optarg
            local opt
            if pos then
                optname = a:sub(3, pos - 1)
                opt = find_opt(opts, optname)
                if opt.arg == "none" then option_error(opts, "--" .. opt.long .. " takes no arg") end
                optarg = a:sub(pos + 1)
            else
                optname = a:sub(3)
                opt = find_opt(opts, optname)
                if opt.arg ~= "none" and i ~= #arg then
                    if arg[i + 1]:sub(1, 1) == "-" and opt.arg == "required" then miss_arg(opts, "--" .. optname) end
                    optarg = arg[i + 1]
                    i = i + 1
                elseif opt.arg == "required" then
                    miss_arg(opts, "--" .. optname)
                end
            end

            parsed[optname] = opt
            parsed[optname].arg = optarg
            count = count + 1
        elseif a:sub(1, 1) == "-" then
            for j = 2, #a do
                local opt = find_opt(opts, a:sub(j, j))
                local optarg

                if opt.arg ~= "none" then
                    if #a == j then
                        if i == #arg then miss_arg(opts, "-" .. opt.short) end
                        optarg = arg[i + 1]
                        i = i + 1
                    else
                        optarg = a:sub(j + 1)
                    end
                    parsed[opt.long] = opt
                    parsed[opt.long].arg = optarg
                    break
                else
                    parsed[opt.long] = opt
                    parsed[opt.long].arg = optarg
                end
            end
        else
            table.insert(nonoptions, a)
        end

        i = i + 1
    end

    return parsed, nonoptions
end

----- end of lua implementation of getopt_long(3) -----

---@overload fun(cmd: string): string, true?, "exit" | "signal"?, number?
---@overload fun(cmd: string, perline: true): string[], true?, "exit" | "signal"?, number?
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

local function die(fmt, ...)
    io.stderr:write(string.format(fmt .. "\n", ...))
    os.exit(1)
end

local function fsh(fmt, ...) return sh(fmt:format(...)) end
local function esh(fmt, ...) if not os.execute(fmt:format(...)) then die("cmd failed: %s", fmt:format(...)) end end
local function println(fmt, ...) io.write(string.format(fmt .. "\n", ...)) end

---@return boolean
local function yesno(fmt, ...)
    io.write(string.format(fmt, ...) .. " (y/n)? ")
    local response = io.read("*l")
    return response:lower() == "y"
end

---@generic T
---@param sep string separator
---@param tbl T[] list to join over sep
---@return string
local function join(sep, tbl)
    local res = ""
    for _, v in ipairs(tbl) do res = res .. v .. sep end
    res = res:sub(1, -2)
    return res
end

---@return string[]
local function installed_pkgs()
    if _G.have then return _G.have end
    local have = {}
    local installed = sh("dpkg-query --show --showformat '${Package}\n'", true)
    for _, pkg in pairs(installed) do have[pkg] = true end
    _G.have = have
    return have
end

---if username is of the form firstname_lastname, parse to get firstname and lastname
---@return string?, string? # guesses
local function try_guess_name()
    local username = os.getenv("USER")
    if not username then return end
    local underscore = username:find("_")
    if not underscore then return end
    return username:sub(1, underscore - 1):lower(), username:sub(underscore + 1):lower()
end

local function upperone(s) return s:sub(1, 1):upper() .. s:sub(2) end

---@return string firstname
---@return string lastname
local function get_firstname_lastname()
    local firstname, lastname = try_guess_name()

    while true do
        if firstname and lastname then
            println("user.name: %s %s", upperone(firstname), upperone(lastname))
            println("user.email: %s_%s@student.waylandps.org", firstname, lastname)
            local correct = yesno("is this correct")
            if correct then break end
        end

        io.write("first name: ")
        firstname = io.read("*l")
        io.write("last name: ")
        lastname = io.read("*l")
    end

    return firstname, lastname
end

---@param firstname string
---@param lastname string
local function set_git_ids(firstname, lastname)
    assert(installed_pkgs()["git"])
    assert(firstname, lastname)
    fsh([[
    git config --global user.name "%s %s"
    git config --global user.email "%s_%s@student.waylandps.org"
    ]], firstname, lastname)
end

local default_install_packages = {
    "wget", "pv", "pigz", "tar", "git", "gh", "libicu-dev", "libnspr4", "libnss3", "clang-format", "nautilus"
}

local function setup_git() set_git_ids(get_firstname_lastname()) end

local function install_pkgs(requested)
    requested = requested or default_install_packages

    local to_install = {}
    for _, pkg in pairs(requested) do
        if not installed_pkgs()[pkg] then table.insert(to_install, pkg) end
    end
    if not next(to_install) then return end

    println("installing %d packages", #to_install)
    esh [[sudo apt-get update]]
    esh([[sudo apt-get install --yes %s]], join(" ", to_install))
    for _, v in pairs(to_install) do _G.have[v] = true end
end

local function install_gitkraken()
    esh [[
    wget -O /tmp/gitkraken.deb https://release.gitkraken.com/linux/gitkraken-amd64.deb
    sudo apt-get install --yes /tmp/gitkraken.deb
    rm /tmp/gitkraken.deb
    ]]
end

---@param path string input path
---@return string path like realpath but not with symlinks
local function absolute_path(path)
    local homedir = os.getenv("HOME")
    if path:sub(1, 1) == "~" then return homedir .. path:sub(2) end
    if path:sub(1, 1) == "/" then return path end
    return os.getenv("PWD") .. "/" .. path
end

-- documentation for lfs in the form of type annotations
--
-- when something returns T?, string?, it either returns T or nil, string
-- when something returns boolean?, string? specifically, the boolean is always `true`
---@class lfs
---@field attributes        fun(path: string, request_or_result?: string | table):             attributes?, string?, number?
---@field chdir             fun(path: string):                                                 boolean?,    string?
---@field lock_dir          fun(path: string, seconds_stale?: number):                         lock?,       string?
---@field currentdir        fun():                                                             string?,     string?
---@field dir               fun(path: string):                                                 dir_iter,    dir_obj
---@field lock              fun(handle: file*, mode: string, start?: number, length?: number): boolean?,    string?
---@field link              fun(link_target: string, link_name: string, symlink?: boolean):    boolean?,    string?
---@field mkdir             fun(dirname: string):                                              boolean?,    string?
---@field rmdir             fun(dirname: string):                                              boolean?,    string?
---@field setmode           fun(path: string, mode: string):                                   string?,     string?
---@field symlinkattributes fun(path: string, request_name?: string):                          link_attrs?, string?, number?
---@field touch             fun(path: string, atime?: number, mtime?: number):                 boolean?,    string?
---@field unlock            fun(handle: file*, start?: number, length?: number):               boolean?,    string?
---
---@class attributes
---@field dev number
---@field ino number
---@field mode "file" | "directory" | "link" | "socket" | "named pipe" | "char device" | "block device" | "other"
---@field nlink number
---@field uid number\
---@field gid number
---@field rdev number
---@field access number
---@field modification number
---@field change number
---@field size number
---@field permissions string
---@field blocks? number
---@field blksize? number
---
---@class link_attrs: attributes
---@field target string
---
---@class dir_obj
---@field next fun(dir_obj): string
---@field close fun(): nil
---
---@alias dir_iter fun(ob: dir_obj, last?: string): string
---@alias lock { free: fun() }

---@return lfs
local function need_lfs()
    local success, lfs = pcall(require, "lfs")
    if not success then die("need lfs installed (lua-filesystem on debian)") end
    return lfs
end

local function gh_login()
    local has_credentials = os.execute [[git config get credential.https://github.com.helper >/dev/null 2>&1]]
    if has_credentials then
        println("existing credentials for https://github.com found")
        return
    end
    os.execute [[gh auth login --git-protocol HTTPS --hostname github.com --web]]
end

---@param where_to string target for cloning operations
local function clone_frc_repo(where_to)
    where_to = absolute_path(where_to or "~/FRC/")
    local lfs = need_lfs()

    local repo_stat = lfs.attributes(where_to)
    if repo_stat and repo_stat.mode == "directory" then return end
    fsh([[
    git clone https://github.com/team5735/FRC %s
    ]], where_to)
end

---@param repo_dir string what repo to setup pre-push for
local function create_pre_push(repo_dir)
    repo_dir = absolute_path(repo_dir or "~/FRC/")
    local pre_push_path = repo_dir .. "/.git/hooks/pre-push"
    local lfs = need_lfs()

    if lfs.attributes(pre_push_path) then os.rename(pre_push_path, repo_dir .. "/.git/hooks/pre-push.bak") end
    local fd = assert(io.open(pre_push_path, "w"))
    fd:write([===[
#!/bin/bash
set -e -o pipefail
PS4=$'P \t$EPOCHREALTIME '

zeroes=$(git hash-object --stdin </dev/null | tr '[0-9a-f]' '0')

found_head=0
head="$(git rev-parse HEAD)"
while read local_ref local_id remote_ref remote_id; do
    # find HEAD
    [[ "$local_id" = "$zeroes" ]] && continue
    [[ "$local_id" != "$head" ]] && continue

    response="$("$(git rev-parse --show-toplevel)"/format.java.sh --no-ask)"
    [[ "$response" != "nothing formatted" ]] && echo commit formatting, please push again && exit 1
    found_head=1
done
]===])
    fd:close()

    fsh([[ chmod +x %s ]], pre_push_path)
end

local function parse_version(version)
    local year = tonumber(version:match("(%d%d%d%d).*"))
    local function compat(if_2027, otherwise) return year >= 2027 and if_2027 or otherwise end
    local dir = string.format("WPILib_%s-%s", compat("Linux-x64", "Linux"), version)
    local file = dir .. ".tar.gz"
    local url = string.format(
        [[https://packages.wpilib.workers.dev/installer/v%s/%s%s]],
        version, compat("", "Linux/"), file
    )
    dir = absolute_path("~/" .. dir)
    file = absolute_path("~/" .. file)
    return year >= 2027, dir, file, url
end

local function check_can_reach_archive(version)
    local _, _, _, url = parse_version(version)
    local output = sh([[2>&1 wget --spider ]] .. url .. " && echo (reached endpoint successfully)")
    if not output:match("(reached endpoint successfully)") then
        io.write(output)
        die("i can't reach the WPILib archive right now, try again later")
    end
end

local function install_wpilib(version, dont_check)
    if not dont_check then check_can_reach_archive(version) end
    local is_2027, dir, file, url = parse_version(version)
    local lfs = need_lfs()
    local attr = lfs.attributes(dir)
    if attr and attr.mode == "directory" then
        println("found WPILib download for %s at %s, skipping download", version, dir)
    else
        fsh([[
        dir=%s file=%s url=%s
        wget --quiet --show-progress "$url" -O "$file"
        rm --recursive --force "$dir"
        size="$(pigz --list "$file" | cut --delimiter ' ' --fields 2)"
        unpigz --to-stdout "$file" | pv --interval 0.2 --name extract --size "$size" | tar --extract --file -
        rm "$file"
        ]], dir, url, file)
    end

    if is_2027 then
        fsh([[ %s/WPILibInstaller-CLI --yes --install-mode all ]], dir)
    else
        println [[

        instructions for the installer window:
        press "Start", "Install for this User", then "Download for this computer only"
        when it becomes available, press the button labeled "Next"
        after installation has succeeded, press "Finish"
        ]]
        fsh([[ %s/WPILibInstaller ]], dir)
    end
end

local function list_dir(dirname)
    dirname = absolute_path(dirname)
    local lfs = require("lfs")
    local results = {}
    for name in lfs.dir(dirname) do table.insert(results, dirname .. name) end
    return results
end

local function list_and_ask_versions()
    local installs = {}
    for _, p in pairs(list_dir("~/wpilib/")) do table.insert(installs, p) end
    for _, p in pairs(list_dir("~/.local/share/wpilib/")) do table.insert(installs, p) end

    for i, install in ipairs(installs) do
        local year = install:match(".*/wpilib/(%d%d%d%d).*")
        println("(%d) WPILib %d at %s", i, year, install)
    end

    io.write("enter which WPILib to uninstall: ")
    local choice = tonumber(io.read("*l"))
    if not choice or not installs[choice] then
        println("aborted!")
        return
    end
    return installs[choice]
end

local function uninstall_wpilib(where)
    where = where or list_and_ask_versions()
    local may_delete = yesno("delete %s", where)
    if not may_delete then
        println("nothing was changed")
        return
    end

    fsh([[rm -vrf %s]], where)
    local year = assert(where:match(".*/wpilib/(%d%d%d%d).*"))
    fsh([[rm -v ~/.local/share/applications/*%d.desktop]], year)
    fsh([[rm -v ~/Desktop/*%d.desktop]], year)
    sh [[sudo update-desktop-database]]
    println("done~!")
end

-- start of execution --

local options = {
    { short = "g", long = "setup-git",           arg = "none",     callback = setup_git },
    { short = "i", long = "install-needed-pkgs", arg = "none",     callback = install_pkgs },
    { short = "l", long = "gh-login",            arg = "none",     callback = gh_login },
    { short = "c", long = "clone-frc-repo",      arg = "required", callback = clone_frc_repo },
    { short = "p", long = "create-pre-push",     arg = "required", callback = create_pre_push },
    { short = "w", long = "install-wpilib",      arg = "required", callback = install_wpilib },
    { short = "k", long = "install-gitkraken",   arg = "none",     callback = install_gitkraken },
    { short = "u", long = "uninstall-wpilib",    arg = "optional", callback = uninstall_wpilib },
}

if #arg == 0 then
    io.stderr:write("when giving no arguments, you have to give a wpilib version")
elseif #arg == 1 and arg[1]:sub(1, 1) ~= "-" then
    local firstname, lastname = get_firstname_lastname()
    install_pkgs()
    install_gitkraken()
    set_git_ids(firstname, lastname)
    gh_login()
    clone_frc_repo("~/FRC")
    create_pre_push("~/FRC")
    install_wpilib(arg[1])

    println("done~!")
else
    local parsed = getopt(options)
    for _, opt in pairs(parsed) do opt.callback(opt.arg) end
end
