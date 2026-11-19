# netdata-ssl

Netdata built with OpenSSL and served over HTTPS on the normal Netdata port.
This is a drop-in replacement for the stock OpenWrt "netdata" package for
routers where the dashboard must be embedded in an HTTPS LuCI page.

## Packages

- Package name: netdata-ssl
- Binary/init/config paths are the same as netdata: /usr/sbin/netdata,
  /etc/init.d/netdata, /etc/config/netdata.
- The package declares PROVIDES:=netdata and CONFLICTS:=netdata. Do not select
  the stock netdata package at the same time.

## UCI options

    config netdata
        option enabled '0'
        option port '19999'
        option enable_ssl '0'
        option cert_file '/etc/netdata/cert.crt'
        option key_file '/etc/netdata/cert.key'

Optional nginx reverse-proxy mode:

    option nginx_support '1'   # Netdata stays HTTP, nginx terminates TLS
    option auth '1'
    option user_passwd 'user:$apr1$...'

With nginx_support disabled (the default), Netdata itself serves TLS using the
certificate configured above.

## TLS certificates

When enable_ssl=1 and the configured certificate/key do not exist, the init
generates a self-signed certificate for the router hostname and LAN IP. The
LuCI app normally installs a certificate that the browser already trusts (the
uhttpd or nginx certificate), so this generation is only a package-only
fallback.

## Service behavior

- The init follows the UCI enabled flag. Setting it to 0 stops a running
  instance gracefully with SIGTERM (procd), then returns.
- stop_service no longer exists; rc.common's procd_kill handles SIGTERM and
  the instance term_timeout is 10 seconds, so Netdata can flush its database.
- respawn is bounded to 5 restarts within one hour with a 5 second retry delay.
- A missing TLS certificate refuses the start with a syslog message instead of
  entering a respawn loop.

## nginx mode

The nginx helper keeps /etc/nginx/conf.d/netdata.locations in sync:

- proxy_pass points to http://127.0.0.1:<port>/ with HTTP/1.1, buffering off
  and a long read timeout for streaming charts.
- auth_basic and auth_basic_user_file are enabled or disabled together. The
  shipped htpasswd file is empty; an authentication request without a valid
  username:password hash is logged and disabled, never replaced by a known
  default password.

## Build

    cd openwrt
    git clone https://github.com/caiwx86/openwrt-netdata-ssl.git package/netdata-ssl
    make menuconfig
    # Administration -> netdata-ssl
    make package/netdata-ssl/compile V=s

## License

GPL-3.0-or-later. See LICENSE.
