-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.admin.status", package.seeall)

function index()
	entry({"admin", "status", "overview"}, template("admin_status/index"), _("Overview"), 1)

	entry({"admin", "status", "iptables"}, template("admin_status/iptables"), _("Firewall"), 2).leaf = true
	entry({"admin", "status", "iptables_dump"}, call("dump_iptables")).leaf = true
	entry({"admin", "status", "iptables_action"}, post("action_iptables")).leaf = true

	entry({"admin", "status", "routes"}, template("admin_status/routes"), _("Routes"), 3)
	entry({"admin", "status", "syslog"}, call("action_syslog"), _("System Log"), 4)
	if not nixio.fs.access("/etc/adv_luci_disabled") then
	entry({"admin", "status", "dmesg"}, call("action_dmesg"), _("Kernel Log"), 5)
	entry({"admin", "status", "processes"}, form("admin_status/processes"), _("Processes"), 6)
	end

	entry({"admin", "status", "realtime"}, alias("admin", "status", "realtime", "load"), _("Realtime Graphs"), 7)

	entry({"admin", "status", "realtime", "load"}, template("admin_status/load"), _("Load"), 1).leaf = true
	entry({"admin", "status", "realtime", "load_status"}, call("action_load")).leaf = true

	entry({"admin", "status", "realtime", "bandwidth"}, template("admin_status/bandwidth"), _("Traffic"), 2).leaf = true
	entry({"admin", "status", "realtime", "bandwidth_status"}, call("action_bandwidth")).leaf = true

	if nixio.fs.access("/etc/config/wireless") then
		entry({"admin", "status", "realtime", "wireless"}, template("admin_status/wireless"), _("Wireless"), 3).leaf = true
		entry({"admin", "status", "realtime", "wireless_status"}, call("action_wireless")).leaf = true
	end

	entry({"admin", "status", "realtime", "connections"}, template("admin_status/connections"), _("Connections"), 4).leaf = true
	entry({"admin", "status", "realtime", "connections_status"}, call("action_connections")).leaf = true

	entry({"admin", "status", "nameinfo"}, call("action_nameinfo")).leaf = true
end

function action_syslog()
	local syslog = luci.sys.syslog()
	luci.template.render("admin_status/syslog", {syslog=syslog})
end

function action_dmesg()
	local dmesg = luci.sys.dmesg()
	luci.template.render("admin_status/dmesg", {dmesg=dmesg})
end

function dump_iptables(family, table)
	local prefix = (family == "6") and "ip6" or "ip"
	local ok, lines = pcall(io.lines, "/proc/net/%s_tables_names" % prefix)
	if ok and lines then
		local s
		for s in lines do
			if s == table then
				local ipt = io.popen(
					"/usr/sbin/%stables -w -t %s --line-numbers -nxvL"
					%{ prefix, table })

				if ipt then
					luci.http.prepare_content("text/plain")

					while true do
						s = ipt:read(1024)
						if not s then break end
						luci.http.write(s)
					end

					ipt:close()
					return
				end
			end
		end
	end

	luci.http.status(404, "No such table")
	luci.http.prepare_content("text/plain")
end

function action_iptables()
	if luci.http.formvalue("zero") then
		if luci.http.formvalue("family") == "6" then
			luci.util.exec("/usr/sbin/ip6tables -Z")
		else
			luci.util.exec("/usr/sbin/iptables -Z")
		end
	elseif luci.http.formvalue("restart") then
		luci.util.exec("/etc/init.d/firewall restart")
	end

	luci.http.redirect(luci.dispatcher.build_url("admin/status/iptables"))
end

function action_bandwidth(iface)
	luci.http.prepare_content("application/json")

	local bwc = io.popen("luci-bwc -i %s 2>/dev/null"
		% luci.util.shellquote(iface))

	if bwc then
		luci.http.write("[")

		while true do
			local ln = bwc:read("*l")
			if not ln then break end
			luci.http.write(ln)
		end

		luci.http.write("]")
		bwc:close()
	end
end

function action_wireless(iface)
	luci.http.prepare_content("application/json")

	local bwc = io.popen("luci-bwc -r %s 2>/dev/null"
		% luci.util.shellquote(iface))

	if bwc then
		luci.http.write("[")

		while true do
			local ln = bwc:read("*l")
			if not ln then break end
			luci.http.write(ln)
		end

		luci.http.write("]")
		bwc:close()
	end
end

function action_load()
	luci.http.prepare_content("application/json")

	local bwc = io.popen("luci-bwc -l 2>/dev/null")
	if bwc then
		luci.http.write("[")

		while true do
			local ln = bwc:read("*l")
			if not ln then break end
			luci.http.write(ln)
		end

		luci.http.write("]")
		bwc:close()
	end
end

function action_connections()
	local sys = require "luci.sys"

	luci.http.prepare_content("application/json")

	luci.http.write('{ "connections": ')
	luci.http.write_json(sys.net.conntrack())

	local bwc = io.popen("luci-bwc -c 2>/dev/null")
	if bwc then
		luci.http.write(', "statistics": [')

		while true do
			local ln = bwc:read("*l")
			if not ln then break end
			luci.http.write(ln)
		end

		luci.http.write("]")
		bwc:close()
	end

	luci.http.write(" }")
end

function action_nameinfo(...)
	local util = require "luci.util"

	luci.http.prepare_content("application/json")
	luci.http.write_json(util.ubus("network.rrdns", "lookup", {
		addrs = { ... },
		timeout = 5000,
		limit = 1000
	}) or { })
end
