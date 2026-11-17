require("luci.sys")

local m

m = Map("AdGuardHome", translate("诊断"))
m.description = translate("服务、配置、端口、防火墙与日志检查")
m.submit = false
m.reset = false
m.apply_on_parse = false

m:section(SimpleSection).template = "AdGuardHome/diag"

return m
