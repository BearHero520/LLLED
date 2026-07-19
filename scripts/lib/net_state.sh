#!/bin/bash

NET_SPEED_CACHE_FILE="${NET_SPEED_CACHE_FILE:-/run/llled/net-speed.cache}"
NET_STATE_CACHE_FILE="${NET_STATE_CACHE_FILE:-/run/llled/net-state.cache}"
NET_SYS_CLASS_DIR="${NET_SYS_CLASS_DIR:-/sys/class/net}"

net_ping_any() {
    local host
    for host in "$@"; do
        timeout 3 ping -c 1 -W 2 "$host" >/dev/null 2>&1 && return 0
    done
    return 1
}

net_probe_state() {
    local domestic=0 overseas=0 domestic_pid overseas_pid
    net_ping_any 223.5.5.5 114.114.114.114 & domestic_pid=$!
    net_ping_any 8.8.8.8 1.1.1.1 & overseas_pid=$!
    wait "$domestic_pid" && domestic=1
    wait "$overseas_pid" && overseas=1

    if [[ $overseas -eq 1 ]]; then
        printf 'vpn|%s|%s\n' "$domestic" "$overseas"
    elif [[ $domestic -eq 1 ]]; then
        printf 'connected|%s|%s\n' "$domestic" "$overseas"
    else
        printf 'disconnected|%s|%s\n' "$domestic" "$overseas"
    fi
}

net_detect_state_cached() {
    local ttl="${1:-30}" now cached_at state domestic overseas sample
    now=$(date +%s)
    if [[ -f "$NET_STATE_CACHE_FILE" ]]; then
        IFS='|' read -r cached_at state domestic overseas < "$NET_STATE_CACHE_FILE" 2>/dev/null || true
        if [[ "$cached_at" =~ ^[0-9]+$ ]] && (( now - cached_at < ttl )); then
            printf '%s|%s|%s\n' "${state:-disconnected}" "${domestic:-0}" "${overseas:-0}"
            return
        fi
    fi

    sample=$(net_probe_state)
    IFS='|' read -r state domestic overseas <<< "$sample"
    printf '%s|%s|%s|%s\n' "$now" "$state" "$domestic" "$overseas" > "${NET_STATE_CACHE_FILE}.tmp.$$"
    mv "${NET_STATE_CACHE_FILE}.tmp.$$" "$NET_STATE_CACHE_FILE"
    printf '%s\n' "$sample"
}

net_interfaces() {
    local dev path found=0
    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r dev; do
            [[ -r "$NET_SYS_CLASS_DIR/$dev/statistics/rx_bytes" ]] || continue
            printf '%s\n' "$dev"
            found=1
        done < <(ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | sort -u)
    fi
    [[ $found -eq 1 ]] && return

    for path in "$NET_SYS_CLASS_DIR"/*; do
        [[ -d "$path" ]] || continue
        dev=$(basename "$path")
        [[ "$dev" == "lo" || "$dev" =~ ^(docker|veth|virbr|br-|tun|tap) ]] && continue
        [[ -r "$path/statistics/rx_bytes" ]] && printf '%s\n' "$dev"
    done
}

net_byte_totals() {
    local dev value rx=0 tx=0
    while IFS= read -r dev; do
        value=$(cat "$NET_SYS_CLASS_DIR/$dev/statistics/rx_bytes" 2>/dev/null || echo 0)
        rx=$((rx + ${value:-0}))
        value=$(cat "$NET_SYS_CLASS_DIR/$dev/statistics/tx_bytes" 2>/dev/null || echo 0)
        tx=$((tx + ${value:-0}))
    done < <(net_interfaces)
    printf '%s %s\n' "$rx" "$tx"
}

net_sample_speed() {
    local rx_now tx_now rx_old tx_old sampled_at now elapsed rx_delta tx_delta rx_kbps tx_kbps
    mkdir -p "$(dirname "$NET_SPEED_CACHE_FILE")"
    read -r rx_now tx_now < <(net_byte_totals)
    now=$(date +%s)
    if [[ -f "$NET_SPEED_CACHE_FILE" ]]; then
        read -r rx_old tx_old sampled_at < "$NET_SPEED_CACHE_FILE" 2>/dev/null || true
    fi
    rx_old="${rx_old:-$rx_now}"
    tx_old="${tx_old:-$tx_now}"
    sampled_at="${sampled_at:-$now}"
    elapsed=$((now - sampled_at))
    (( elapsed < 1 )) && elapsed=1
    rx_delta=$((rx_now - rx_old))
    tx_delta=$((tx_now - tx_old))
    (( rx_delta < 0 )) && rx_delta=0
    (( tx_delta < 0 )) && tx_delta=0
    rx_kbps=$((rx_delta / 1024 / elapsed))
    tx_kbps=$((tx_delta / 1024 / elapsed))
    printf '%s %s %s\n' "$rx_now" "$tx_now" "$now" > "${NET_SPEED_CACHE_FILE}.tmp.$$"
    mv "${NET_SPEED_CACHE_FILE}.tmp.$$" "$NET_SPEED_CACHE_FILE"
    printf '%s|%s|%s\n' "$rx_kbps" "$tx_kbps" "$((rx_kbps + tx_kbps))"
}
