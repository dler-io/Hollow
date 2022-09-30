#!/usr/bin/env bash
echo=echo
for cmd in echo /bin/echo; do
    $cmd >/dev/null 2>&1 || continue

    if ! $cmd -e "" | grep -qE '^-e'; then
        echo=$cmd
        break
    fi
done

CSI=$($echo -e "\033[")
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"

CLEANUP() {
    for file in /var/log/*
    do
        if [ -f $file ]; then
            echo > $file
        fi
    done
}

OUT_ALERT() {
    echo -e "${CYELLOW} $1 ${CEND}"
}

ERR_CLEANUP() {
    echo -e "${CRED} $1 ${CEND}"
}

OUT_INFO() {
    echo -e "${CCYAN} $1 ${CEND}"
}

ERR_CLEANUP() {
    CLEANUP
    ERR_CLEANUP "$1"

    exit 1
}

if [[ $1 == "remove" ]]; then
    docker stop hollow
    docker rm hollow
    yes | docker system prune -a

    rm -rf /etc/hollow

    OUT_INFO "[✓] Hollow 卸载完毕"
    CLEANUP
    exit 0
fi

if [[ $1 == "update" ]]; then
    DOCKER_UP

    OUT_INFO "[✓] Hollow 更新完毕"
    CLEANUP
    exit 0
fi

OPTIMIZE() {
    OUT_ALERT "[✓] 正在优化系统参数中"

    ulimit -n 512000

    chattr -i /etc/sysctl.conf
    cat > /etc/sysctl.conf << EOF
fs.file-max = 512000
net.core.default_qdisc = fq
net.core.netdev_max_backlog = 512000
net.core.rmem_default = 26214400
net.core.rmem_max = 26214400
net.core.somaxconn = 512000
net.core.wmem_default = 26214400
net.core.wmem_max = 26214400
net.ipv4.ip_no_pmtu_disc = 1
net.ipv4.ip_default_ttl = 128
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.ip_local_reserved_ports = 1234
net.ipv4.neigh.default.gc_interval = 30
net.ipv4.neigh.default.gc_stale_time = 30
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 3
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_time = 10
net.ipv4.tcp_max_syn_backlog = 10240
net.ipv4.tcp_max_tw_buckets = 10240
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_rmem = 4096 65536 4194304
net.ipv4.tcp_sack = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_wmem = 4096 65536 4194304
net.netfilter.nf_conntrack_generic_timeout = 120
net.netfilter.nf_conntrack_icmp_timeout = 3
net.netfilter.nf_conntrack_max = 512000
net.netfilter.nf_conntrack_tcp_max_retrans = 3
net.netfilter.nf_conntrack_tcp_timeout_close = 3
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 3
net.netfilter.nf_conntrack_tcp_timeout_established = 120
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 3
net.netfilter.nf_conntrack_tcp_timeout_last_ack = 3
net.netfilter.nf_conntrack_tcp_timeout_max_retrans = 3
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 3
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 3
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 3
net.netfilter.nf_conntrack_tcp_timeout_unacknowledged = 3
net.netfilter.nf_conntrack_udp_timeout = 3
net.netfilter.nf_conntrack_udp_timeout_stream = 30
vm.swappiness = 0
EOF

    cat > /etc/security/limits.conf << EOF
* soft nofile 512000
* hard nofile 512000
* soft nproc 512000
* hard nproc 512000
root soft nofile 512000
root hard nofile 512000
root soft nproc 512000
root hard nproc 512000
EOF

    sysctl -p
}

OUT_ALERT "[✓] 同步时间中"
timedatectl set-timezone Asia/Shanghai
ntpdate pool.ntp.org || htpdate -s www.baidu.com
hwclock -w

if [ ! -d "/etc/hollow" ]; then
    mkdir /etc/hollow
fi

DOCKER_INSTALL() {
    docker_exists=$(docker version 2>/dev/null)
    if [[ ${docker_exists} == "" ]]; then
        OUT_ALERT "[✓] 正在安装docker"

        apt install docker.io -y
    fi

    docker_compose_exists=$(docker-compose version 2>/dev/null)
    if [[ ${docker_compose_exists} == "" ]]; then
        OUT_ALERT "[✓] 正在安装docker-compose"

        curl --connect-timeout 5 -L https://compose.dler.workers.dev/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose || curl -L --fail https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

cat > /etc/hollow/docker-compose.yml << EOF
version: '3'
services:
  relay:
    image: "dlerio/hollow:latest"
    container_name: hollow
    restart: always
    network_mode: host
    privileged: true
    volumes:
      - /etc/timezone:/etc/timezone
      - /etc/localtime:/etc/localtime
      - /sys/fs/bpf:/sys/fs/bpf
      - ./config.toml:/config.toml
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

if [[ -n "$1" ]]; then
    curl -L --fail $1 -o /etc/hollow/config.toml || ERR_CLEANUP "[✕] 下载Hollow 配置文件失败"
fi

DOCKER_UP() {
    chmod +x /etc/hollow
    cd /etc/hollow

    if [ ! -f "/etc/hollow/docker-compose.yml" ]; then
        ERR_CLEANUP "[✕] docker-compose.yml 不存在"
    fi

    if [ ! -f "/etc/hollow/config.toml" ]; then
        ERR_CLEANUP "[✕] config.toml 不存在"
    fi

    docker-compose pull
    docker-compose up -d --force-recreate
}

main=`uname -r | awk -F . '{print $1}'`
minor=`uname -r | awk -F . '{print $2}'`
if [ $main -gt "5" ]; then
    OUT_ALERT "[✓] 系统内核版本高于5.10"
elif [ $main -ge "5" ] && [ $minor -ge "10" ]; then
    OUT_ALERT "[✓] 系统内核版本高于5.10"
else
    ERR_CLEANUP "[✕] 系统内核版本低于5.10"
fi

DOCKER_INSTALL
OPTIMIZE

DOCKER_UP

OUT_INFO "[✓] Hollow 部署完毕"
CLEANUP
exit 0
