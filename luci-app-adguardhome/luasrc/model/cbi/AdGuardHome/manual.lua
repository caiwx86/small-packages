local m, s, o
local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
require("string")
require("io")
require("table")

m = Map("AdGuardHome")



local configpath = uci:get("AdGuardHome", "AdGuardHome", "configpath") or "/etc/AdGuardHome.yaml"
local binpath = uci:get("AdGuardHome", "AdGuardHome", "binpath") or "/usr/bin/AdGuardHome"

local function shell_quote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

s = m:section(TypedSection, "AdGuardHome")
s.anonymous = true
s.addremove = false

o = s:option(TextValue, "escconf")
o.rows = 66
o.wrap = "off"
o.rmempty = true

o.cfgvalue = function(self, section)
	local tmp = fs.readfile("/tmp/AdGuardHometmpconfig.yaml")
	if tmp then return tmp end

	local cfg = fs.readfile(configpath)
	if cfg then return cfg end

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

o.validate = function(self, value)
	if not value then return nil end
	fs.writefile("/tmp/AdGuardHometmpconfig.yaml", value:gsub("\r\n", "\n"))
	fs.remove("/tmp/AdGuardHometest.log")

	if not fs.access(binpath) then
		return value
	end

	local ret = sys.call(shell_quote(binpath) ..
		" -c /tmp/AdGuardHometmpconfig.yaml --check-config 2>/tmp/AdGuardHometest.log")
	if ret == 0 then
		return value
	end

	-- Drop the rejected draft, otherwise it is shown again on the next visit.
	fs.remove("/tmp/AdGuardHometmpconfig.yaml")
	luci.http.redirect(luci.dispatcher.build_url("admin", "services", "AdGuardHome", "manual"))
	return nil
end

o.write = function(self, section, value)
	local tmp = "/tmp/AdGuardHometmpconfig.yaml"
	if not fs.access(tmp) then return end

	-- Keep one previous version before replacing the live configuration.
	local current = fs.readfile(configpath)
	if current and current ~= "" then
		fs.writefile(configpath .. ".bak", current)
	end
	fs.move(tmp, configpath)
end

o.remove = function(self, section, value)
	-- Removing the form value must not wipe the live configuration.
	fs.remove("/tmp/AdGuardHometmpconfig.yaml")
end

o = s:option(DummyValue, "")
o.anonymous = true
o.template = "AdGuardHome/yamleditor"

if not fs.access(binpath) then
	o.description = translate("WARNING: no binary found, config validation will be skipped")
end

if fs.access("/tmp/AdGuardHometest.log") then
	local errlog = fs.readfile("/tmp/AdGuardHometest.log")
	if errlog and errlog ~= "" then
		o = s:option(TextValue, "")
		o.readonly = true
		o.rows = 5
		o.rmempty = true
		o.name = ""
		o.cfgvalue = function(self, section)
			return fs.readfile("/tmp/AdGuardHometest.log")
		end
	end
end

function m.on_commit(map)
	-- The YAML is not a UCI config, so procd will not reload on its own.
	io.popen("/etc/init.d/AdGuardHome reload >/dev/null 2>&1 &")
end

return m
