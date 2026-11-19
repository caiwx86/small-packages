# LuCI Netdata

A modern LuCI front-end for [Netdata](https://github.com/netdata/netdata),
built for routers running [netdata-ssl](https://github.com/caiwx86/openwrt-netdata-ssl).

Netdata-ssl is a Netdata build with native TLS support, so the dashboard can be
embedded directly over HTTPS without nginx, extra ports or a reverse proxy.

## Compatibility

- OpenWrt 23.05, 24.10 and 25.12 (opkg and apk based images).
- netdata-ssl (recommended, provides native HTTPS) or the stock netdata
  package (HTTP only), plus openssl-util.
- LuCI JS views, Bootstrap and Material themes, mobile and desktop.
- No nginx dependency and no extra listening port.

## What changed

- HTTPS display is fixed at the protocol level: Netdata itself speaks TLS.
  The app reuses the certificate the browser already trusts for LuCI
  (/etc/uhttpd.crt, or the nginx certificate), or generates a self-signed one
  as a fallback. The iframe uses https://<host>:<port>/ directly.
- Settings are reduced to three options: enable, port and listen address.
  The old nginx toggle, basic-auth fields, certificate paths and logger switch
  are gone.
- The dashboard page has a modern card layout with live status, one-click
  start/stop/restart, fullscreen, reload and settings actions.
- Status is refreshed automatically, the iframe is sized to the viewport
  (no double scrollbars), and stopped/HTTPS states show a clear action card
  instead of a blank frame.
- The service port and listen address are written to /etc/netdata/netdata.conf.
  The stock/netdata-ssl init script applies the port and TLS options itself.
- The old sed-patched init script is detected and replaced with a clean
  netdata-ssl-compatible init.
- The package no longer ships /etc/config/netdata, avoiding a file conflict
  with netdata-ssl. The file is created by uci-defaults only when missing.

## Backend selection (important for build/image inclusion)

This package no longer hard-depends on netdata-ssl. It uses conditional
dependencies so it is still visible and buildable in a stock OpenWrt tree:

    LUCI_DEPENDS:=+openssl-util         +PACKAGE_netdata-ssl:netdata-ssl         +PACKAGE_netdata:netdata

Select exactly one backend in menuconfig:

- Administration -> netdata-ssl -> <*> for native HTTPS (recommended).
  Deselect the stock Administration -> netdata package; the two conflict.
- Or Administration -> netdata -> <*> for HTTP-only. The app detects that the
  init has no TLS support and shows an "install netdata-ssl" hint on HTTPS.

The LuCI app itself must be selected as built-in in menuconfig
(LuCI -> Applications -> luci-app-netdata -> <*>). A module (<M>) is compiled
but not installed into the firmware image.

## Install

The netdata-ssl package must be available in your feed. Add the repository as
a package feed (or copy it to package/netdata-ssl), then:

    opkg update
    opkg install luci-app-netdata

On apk based snapshots:

    apk update
    apk add luci-app-netdata

luci-app-netdata depends on netdata-ssl. Do not install the stock netdata
package at the same time; both provide /usr/sbin/netdata.

Open LuCI and go to Status -> Netdata.

## Companion netdata-ssl fixes

This revision is designed to be used with the companion openwrt-netdata-ssl
patch, which fixes several issues in the package itself:

- stop no longer uses "kill -9". The init uses procd's SIGTERM path and a
  10 second term_timeout, so Netdata can flush its database before exiting.
- the UCI "enabled" flag is authoritative: disabling it stops the service
  gracefully instead of leaving it running or kill -9'ing it on the next start.
- if TLS is enabled but cert_file/key_file are missing, the init generates a
  self-signed certificate (openssl-util is now a dependency) instead of
  crash-looping.
- the nginx helper comments/uncomments both auth_basic and auth_basic_user_file
  together (auth_basic alone makes nginx return 500), proxies to 127.0.0.1 with
  HTTP/1.1, and no longer ships a known default admin password.
- respawn is bounded (3600/5/5) and netdata.conf editing is portable awk instead
  of fragile sed.
- the package declares PROVIDES/CONFLICTS netdata, so it is a clean drop-in
  replacement for the stock package.

Apply the openwrt-netdata-ssl patch before building if you use the packaged
init; the LuCI app's built-in init fallback is already aligned with it.

## Settings

- Enable: start Netdata now and at boot. Unchecking it and pressing
  "Save & Apply" stops the service and disables autostart.
- Service port: HTTP and HTTPS share this port; changing it restarts Netdata.
- Listen address: all interfaces, or localhost only.

Everything else is automatic:

- When LuCI is opened over HTTPS, the app enables TLS on Netdata.
- The certificate is reused from the LuCI web server when possible:
  - uhttpd: /etc/uhttpd.crt and /etc/uhttpd.key
  - nginx: the certificate configured in /etc/config/nginx, or
    /etc/nginx/conf.d/_lan.crt
  - an existing custom certificate configured in UCI is kept
  - otherwise a self-signed certificate is generated for the router hostname
    and LAN IP (browsers may ask you to trust it once).
- When LuCI is opened over HTTP, the dashboard stays on HTTP unless TLS was
  already enabled. Accessing LuCI over HTTPS later switches it on.
- The Advanced tab edits /etc/netdata/netdata.conf. Port and TLS keys are
  managed by the Settings tab; other collectors and update intervals can be
  adjusted there.

## Security

Netdata does not provide built-in user authentication. Keep it reachable only
from the LAN (listen address, firewall, or the "[web] allow connections from"
option) and do not expose the port to the internet. The old nginx basic-auth
option from previous luci-app-netdata versions is no longer used, because the
dashboard now runs over native TLS on the Netdata port.

## Defaults in netdata.conf

The netdata-ssl package ships a netdata.conf with "update every = 2" and the
apps/cgroups collectors disabled, which is suitable for routers. Reduce the
update frequency further on very slow devices from the Advanced tab.

## Troubleshooting

Dashboard is blank after switching to HTTPS
: The certificate may not be trusted. Open https://<router>:<port>/ once in a
  new tab and accept the certificate, then reload LuCI. If the certificate is
  self-signed, LuCI's own certificate is reused whenever it exists, so this is
  normally not needed.

"当前 Netdata 构建不支持 TLS"
: netdata-ssl is not installed, or its init script was replaced. Install /
  reinstall netdata-ssl, then reload the page.

Port change has no effect
: Check that the port is free and that the [web] section in the Advanced tab
  contains "default port = <your port>". The app restarts Netdata after
  applying.

Service does not start
: Run "logread -e netdata" and check the port/certificate. The app validates
  the port and listen address before applying.

Too much CPU
: Increase "[global] update every" in the Advanced tab and keep cgroups/apps
  collectors disabled.

## Build

    cd openwrt
    git clone https://github.com/caiwx86/openwrt-netdata-ssl.git package/netdata-ssl
    git clone https://github.com/caiwx86/luci-app-netdata.git package/luci-app-netdata
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    make menuconfig
    # LuCI -> Applications -> luci-app-netdata       -> <*> (not <M>)
    # Administration -> netdata-ssl                  -> <*> (for HTTPS)
    # Administration -> netdata                      -> deselected
    make package/luci-app-netdata/compile V=s

Verify the selection before building the image:

    grep CONFIG_PACKAGE_luci-app-netdata= .config
    grep CONFIG_PACKAGE_netdata-ssl= .config
    grep -R "luci-app-netdata" tmp/.config-package.in

If the app is missing from the firmware, check that it is "=y" (not "=m"),
that a backend is selected, and that the image was rebuilt with
"make image" after the selection change. When using an image profile:

    make image PROFILE=... PACKAGES="luci-app-netdata netdata-ssl"

## License

GPL-3.0. See LICENSE.
