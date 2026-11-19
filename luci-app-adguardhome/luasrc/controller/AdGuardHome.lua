module("luci.controller.AdGuardHome", package.seeall)

local fs = require "nixio.fs"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()

local function shq(value)
	return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function binpath()
	return uci:get("AdGuardHome", "AdGuardHome", "binpath") or "/usr/bin/AdGuardHome"
end

local function service_pids()
	local name = binpath():match("([^/]+)$")
	local pids = {}
	if not name then return pids end
	for path in fs.glob("/proc/*/comm") do
		local comm = fs.readfile(path)
		if comm then
			comm = comm:gsub("%s+$", "")
			if comm == name then
				local pid = path:match("/proc/(%d+)/comm")
				if pid then pids[#pids + 1] = pid end
			end
		end
	end
	table.sort(pids, function(a, b) return tonumber(a) < tonumber(b) end)
	return pids
end

local function service_running()
	if not fs.access(binpath()) then
		return false
	end
	return #service_pids() > 0
end

local function require_post()
	if http.getenv("REQUEST_METHOD") ~= "POST" then
		http.status(405, "Method Not Allowed")
		http.prepare_content("application/json")
		http.write_json({ success = false, message = "POST required" })
		return false
	end
	-- LuCI's session cookie plus POST is required here.  The token is sent by
	-- the UI for future stricter checks, but not enforced to stay compatible
	-- with older LuCI releases where the token name differs.
	return true
end

local function json_result(result)
	http.prepare_content("application/json")
	http.write_json(result)
end

function index()
	-- luci 23.05+ 已通过 menu.d JSON 注册菜单，无需重复注册
	if not nixio.fs.access("/usr/share/luci/menu.d/luci-app-adguardhome.json") then
		local page = entry({"admin", "services", "AdGuardHome"},
			alias("admin", "services", "AdGuardHome", "overview"),
			_("AdGuard Home"), 10)
		page.dependent = true
		page.acl_depends = { "luci-app-adguardhome" }

		entry({"admin", "services", "AdGuardHome", "overview"},
			cbi("AdGuardHome/overview"), _("概览"), 1).leaf = true
		entry({"admin", "services", "AdGuardHome", "base"},
			cbi("AdGuardHome/base"), _("基础设置"), 2).leaf = true
		entry({"admin", "services", "AdGuardHome", "tools"},
			cbi("AdGuardHome/tools"), _("运维"), 3).leaf = true
		entry({"admin", "services", "AdGuardHome", "log"},
			form("AdGuardHome/log"), _("日志"), 4).leaf = true
		entry({"admin", "services", "AdGuardHome", "manual"},
			cbi("AdGuardHome/manual"), _("手动配置"), 5).leaf = true
		entry({"admin", "services", "AdGuardHome", "diag"},
			cbi("AdGuardHome/diag"), _("诊断"), 6).leaf = true
	end

	-- API 路由在新旧版本均需注册
	entry({"admin", "services", "AdGuardHome", "status"},
		call("act_status"), nil).leaf = true
	entry({"admin", "services", "AdGuardHome", "toggle"},
		call("toggle_service"), nil).leaf = true
	entry({"admin", "services", "AdGuardHome", "check"},
		call("check_update"), nil)
	entry({"admin", "services", "AdGuardHome", "doupdate"},
		call("do_update"), nil)
	entry({"admin", "services", "AdGuardHome", "getlog"},
		call("get_log"), nil)
	entry({"admin", "services", "AdGuardHome", "dodellog"},
		call("do_dellog"), nil)
	entry({"admin", "services", "AdGuardHome", "reloadconfig"},
		call("reload_config"), nil)
	entry({"admin", "services", "AdGuardHome", "gettemplateconfig"},
		call("get_template_config"), nil)
	entry({"admin", "services", "AdGuardHome", "repair"},
		call("do_repair"), nil)
	entry({"admin", "services", "AdGuardHome", "backupconfig"},
		call("do_backup_config"), nil)
	entry({"admin", "services", "AdGuardHome", "restoreconfig"},
		call("do_restore_config"), nil)
	entry({"admin", "services", "AdGuardHome", "rollbackcore"},
		call("do_rollback_core"), nil)
	entry({"admin", "services", "AdGuardHome", "systemlog"},
		call("get_system_log"), nil)
end

local function gen_template_config()
	local dns_servers = ""
	local resolv_auto = "/tmp/resolv.conf.d/resolv.conf.auto"
	if fs.access(resolv_auto) then
		for line in io.lines(resolv_auto) do
			local ns = line:match("^[^#]*nameserver%s+([^%s]+)")
			if ns then
				dns_servers = dns_servers .. "  - " .. ns .. "\n"
			end
		end
	end

	local tmpl = "/usr/share/AdGuardHome/AdGuardHome_template.yaml"
	local f = io.open(tmpl, "r")
	if not f then return "" end

	local lines = {}
	for line in f:lines() do
		if line == "#bootstrap_dns" then
			table.insert(lines, dns_servers)
		elseif line == "#upstream_dns" then
			table.insert(lines, dns_servers)
		else
			table.insert(lines, line)
		end
	end
	f:close()
	return table.concat(lines, "\n")
end

function get_template_config()
	http.prepare_content("text/plain; charset=utf-8")
	http.write(gen_template_config())
end

function reload_config()
	fs.remove("/tmp/AdGuardHometmpconfig.yaml")
	http.prepare_content("application/json")
	http.write('{}')
end

function act_status()
	local result = {}
	result.running = service_running()

	local redir = fs.readfile("/var/run/AdGredir")
	result.redirect = (redir == "1")

	http.prepare_content("application/json")
	http.write_json(result)
end

function do_repair()
	if not require_post() then return end
	local auto = http.formvalue("auto") == "1" and " auto" or ""
	local output = luci.sys.exec("/etc/init.d/AdGuardHome repair" .. auto .. " 2>&1")
	local enabled = uci:get("AdGuardHome", "AdGuardHome", "enabled") == "1"
	local running = service_running()
	-- Starting procd instances is asynchronous; give them a moment before
	-- reporting the result to the page.
	for _ = 1, 3 do
		if running or not enabled then break end
		luci.sys.call("sleep 1")
		running = service_running()
	end
	local redir = fs.readfile("/var/run/AdGredir")
	local result = {
		success = (not enabled) or running,
		enabled = enabled,
		running = running,
		redirect = (redir == "1"),
		output = output
	}

	if not result.success then
		result.message = "自动修复未完成，请检查系统日志或核心配置。"
	end

	http.prepare_content("application/json")
	http.write_json(result)
end

function do_backup_config()
	if not require_post() then return end
	local configpath = uci:get("AdGuardHome", "AdGuardHome", "configpath") or "/etc/AdGuardHome.yaml"
	local data = fs.readfile(configpath)
	if not data then
		json_result({ success = false, message = "配置文件不存在" })
		return
	end

	local target = configpath .. ".bak." .. os.date("%Y%m%d-%H%M%S")
	if fs.writefile(target, data) == nil then
		json_result({ success = false, message = "备份写入失败" })
		return
	end

	local list = {}
	for path in fs.glob(configpath .. ".bak.*") do list[#list + 1] = path end
	table.sort(list)
	while #list > 5 do
		fs.remove(list[1])
		table.remove(list, 1)
	end

	json_result({ success = true, file = target })
end

function do_restore_config()
	if not require_post() then return end
	local configpath = uci:get("AdGuardHome", "AdGuardHome", "configpath") or "/etc/AdGuardHome.yaml"
	local candidates = {}
	for path in fs.glob(configpath .. ".bak*") do
		if path ~= configpath .. ".before-restore" then
			candidates[#candidates + 1] = path
		end
	end
	table.sort(candidates)
	local src = candidates[#candidates]
	if not src then
		json_result({ success = false, message = "没有可用备份" })
		return
	end

	local binary = binpath()
	-- Only validate when the current core can execute; a broken core must not
	-- prevent restoring a known-good configuration.
	if fs.access(binary) and luci.sys.call(shq(binary) .. " --version >/dev/null 2>&1") == 0 then
		local ret = luci.sys.call(shq(binary) .. " -c " .. shq(src) .. " --check-config >/dev/null 2>&1")
		if ret ~= 0 then
			json_result({ success = false, message = "备份配置未通过校验", file = src })
			return
		end
	end

	local current = fs.readfile(configpath)
	if current then
		fs.writefile(configpath .. ".before-restore", current)
	end
	local data = fs.readfile(src)
	if not data or fs.writefile(configpath, data) == nil then
		json_result({ success = false, message = "恢复失败" })
		return
	end

	luci.sys.call("/etc/init.d/AdGuardHome reload >/dev/null 2>&1 &")
	json_result({ success = true, file = src })
end

function do_rollback_core()
	if not require_post() then return end
	local binary = binpath()
	local old = binary .. ".old"
	if not fs.access(old) then
		json_result({ success = false, message = "没有可回滚的核心" })
		return
	end

	local data = fs.readfile(old)
	if not data then
		json_result({ success = false, message = "读取旧核心失败" })
		return
	end
	local tmp = binary .. ".new"
	if fs.writefile(tmp, data) == nil then
		json_result({ success = false, message = "写入临时核心失败" })
		return
	end
	luci.sys.call("chmod 755 " .. shq(tmp))
	if luci.sys.call("mv -f " .. shq(tmp) .. " " .. shq(binary)) ~= 0 then
		fs.remove(tmp)
		json_result({ success = false, message = "替换核心失败" })
		return
	end

	luci.sys.call("/etc/init.d/AdGuardHome reload >/dev/null 2>&1 &")
	json_result({ success = true })
end

function get_system_log()
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("logread -e AdGuardHome 2>/dev/null | tail -n 400") or "")
end

function toggle_service()
	if not require_post() then return end
	local enabled = http.formvalue("enabled") == "1" and "1" or "0"
	local old_enabled = uci:get("AdGuardHome", "AdGuardHome", "enabled") == "1" and "1" or "0"
	local result = {
		enabled = (enabled == "1")
	}

	-- Preflight: when enabling, make sure the binary is actually present.
	-- Without this, init.d reload silently fails and the UI only sees an
	-- opaque "Operation failed" toast (issue #254).
	if enabled == "1" then
		local binpath = uci:get("AdGuardHome", "AdGuardHome", "binpath") or "/usr/bin/AdGuardHome"
		if not fs.access(binpath) then
			result.success = false
			result.enabled = (old_enabled == "1")
			result.running = false
			result.message = "找不到 AdGuardHome 二进制文件（" .. binpath ..
				"），请先在「运维」页面下载。"
			http.prepare_content("application/json")
			http.write_json(result)
			return
		end
	end

	uci:set("AdGuardHome", "AdGuardHome", "enabled", enabled)
	uci:commit("AdGuardHome")

	local rc
	if enabled == "1" then
		-- Detach the reload from the CGI request so the HTTP call returns
		-- immediately while the daemon comes up. Fully redirecting fds + `&`
		-- is enough — avoid start-stop-daemon, whose busybox applet is not
		-- enabled on some images (e.g. immortalwrt 25.10), where it would
		-- exit 127 and make the toggle wrongly report a start failure (#254).
		rc = luci.sys.call("/etc/init.d/AdGuardHome reload >/dev/null 2>&1 &")
	else
		rc = luci.sys.call("/etc/init.d/AdGuardHome stop >/dev/null 2>&1")
	end

	if enabled == "1" then
		result.running = false
	else
		result.running = service_running()
		for _ = 1, 2 do
			if not result.running then
				break
			end
			luci.sys.call("sleep 1")
			result.running = service_running()
		end
	end

	result.pending = (enabled == "1" and not result.running)
	result.success = (rc == 0) and (enabled == "1" or not result.running)

	if not result.success then
		uci:set("AdGuardHome", "AdGuardHome", "enabled", old_enabled)
		uci:commit("AdGuardHome")
		result.enabled = (old_enabled == "1")
		result.message = enabled == "1" and "AdGuardHome start failed" or "AdGuardHome stop failed"
	end

	http.prepare_content("application/json")
	http.write_json(result)
end

function do_update()
	if not require_post() then return end
	fs.writefile("/var/run/lucilogpos", "0")
	http.prepare_content("application/json")
	http.write('{}')

	local arg = ""
	if luci.http.formvalue("force") == "1" then
		arg = "force"
	end

	local script = "/usr/share/AdGuardHome/update_core.sh"
	if fs.access("/var/run/update_core") then
		if arg == "force" then
			-- Security fix: script 路径是固定常量，arg 只能是 "force" 或 ""，无注入风险
			luci.sys.exec("pkill -f '" .. script .. "' 2>/dev/null; " .. script .. " " .. arg .. " >/tmp/AdGuardHome_update.log 2>&1 &")
		end
	else
		luci.sys.exec(script .. " " .. arg .. " >/tmp/AdGuardHome_update.log 2>&1 &")
	end
end

function get_log()
	local logfile = uci:get("AdGuardHome", "AdGuardHome", "logfile")

	if not logfile or logfile == "" then
		http.write("no log available\n")
		return
	end

	if logfile == "syslog" then
		if not fs.access("/var/run/AdGuardHomesyslog") then
			luci.sys.exec("(/usr/share/AdGuardHome/getsyslog.sh &); sleep 1;")
		end
		logfile = "/tmp/AdGuardHometmp.log"
		fs.writefile("/var/run/AdGuardHomesyslog", "1")
	elseif not fs.access(logfile) then
		http.write("")
		return
	end

	http.prepare_content("text/plain; charset=utf-8")

	local fdp = 0
	if fs.access("/var/run/lucilogreload") then
		fdp = 0
		fs.remove("/var/run/lucilogreload")
	else
		local pos = fs.readfile("/var/run/lucilogpos")
		fdp = tonumber(pos) or 0
	end

	local f = io.open(logfile, "r")
	if not f then
		http.write("")
		return
	end

	f:seek("set", fdp)
	local content = f:read(2048000) or ""
	fdp = f:seek()
	f:close()

	fs.writefile("/var/run/lucilogpos", tostring(fdp))
	http.write(content)
end

function do_dellog()
	if not require_post() then return end
	local logfile = uci:get("AdGuardHome", "AdGuardHome", "logfile")
	if logfile and logfile ~= "" and logfile ~= "syslog" then
		fs.writefile(logfile, "")
	end
	http.prepare_content("application/json")
	http.write('{}')
end

function check_update()
	http.prepare_content("text/plain; charset=utf-8")

	local pos = fs.readfile("/var/run/lucilogpos")
	local fdp = tonumber(pos) or 0

	local f = io.open("/tmp/AdGuardHome_update.log", "r")
	if not f then
		http.write("")
		return
	end

	f:seek("set", fdp)
	local content = f:read(2048000) or ""
	fdp = f:seek()
	f:close()

	fs.writefile("/var/run/lucilogpos", tostring(fdp))

	if fs.access("/var/run/update_core") then
		http.write(content)
	else
		-- Plain-text end marker: a NUL byte here made the template binary.
		local marker = "__AGH_UPDATE_FINISHED__"
		if fs.access("/var/run/update_core_error") then
			marker = "__AGH_UPDATE_FINISHED_ERROR__"
		end
		http.write(content .. "\n" .. marker .. "\n")
	end
end
