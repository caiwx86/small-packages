table inet adguardhome {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;

        __AGH_WAN_RETURN_LINE__

        fib daddr type local udp dport 53 redirect to :__AGH_PORT__
        fib daddr type local tcp dport 53 redirect to :__AGH_PORT__
    }
}
