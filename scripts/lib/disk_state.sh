#!/bin/bash

DISK_IO_CACHE_DIR="${DISK_IO_CACHE_DIR:-/run/llled/disk-io}"
DISKSTATS_FILE="${DISKSTATS_FILE:-/proc/diskstats}"

disk_io_cache_path() {
    printf '%s/%s.io\n' "$DISK_IO_CACHE_DIR" "$(basename "$1")"
}

disk_power_cache_path() {
    printf '%s/%s.power\n' "$DISK_IO_CACHE_DIR" "$(basename "$1")"
}

disk_io_totals() {
    local name
    name=$(basename "$1")
    awk -v disk="$name" '$3 == disk { print $6, $10; exit }' "$DISKSTATS_FILE" 2>/dev/null
}

disk_sample_io() {
    local dev="$1" idle_seconds="${2:-8}" file now elapsed
    local read_now write_now read_old write_old sampled_at last_activity
    local read_delta write_delta read_kbps write_kbps total_kbps active=0

    mkdir -p "$DISK_IO_CACHE_DIR"
    file=$(disk_io_cache_path "$dev")
    read -r read_now write_now < <(disk_io_totals "$dev")
    read_now="${read_now:-0}"
    write_now="${write_now:-0}"
    now=$(date +%s)

    if [[ -f "$file" ]]; then
        read -r read_old write_old sampled_at last_activity < "$file" 2>/dev/null || true
    fi
    read_old="${read_old:-$read_now}"
    write_old="${write_old:-$write_now}"
    sampled_at="${sampled_at:-$now}"
    last_activity="${last_activity:-0}"
    elapsed=$((now - sampled_at))
    (( elapsed < 1 )) && elapsed=1
    read_delta=$((read_now - read_old))
    write_delta=$((write_now - write_old))
    (( read_delta < 0 )) && read_delta=0
    (( write_delta < 0 )) && write_delta=0
    read_kbps=$((read_delta / 2 / elapsed))
    write_kbps=$((write_delta / 2 / elapsed))
    total_kbps=$((read_kbps + write_kbps))

    if (( read_delta > 0 || write_delta > 0 )); then
        last_activity="$now"
    fi
    (( last_activity > 0 && now - last_activity < idle_seconds )) && active=1
    printf '%s %s %s %s\n' "$read_now" "$write_now" "$now" "$last_activity" > "$file"
    printf '%s|%s|%s|%s\n' "$read_kbps" "$write_kbps" "$total_kbps" "$active"
}

disk_power_state_cached() {
    local dev="$1" interval="${2:-60}" file now cached_at cached_state output lower
    file=$(disk_power_cache_path "$dev")
    now=$(date +%s)

    if [[ -f "$file" ]]; then
        IFS='|' read -r cached_at cached_state < "$file" 2>/dev/null || true
        if [[ "$cached_at" =~ ^[0-9]+$ ]] && (( now - cached_at < interval )); then
            printf '%s\n' "${cached_state:-idle}"
            return
        fi
    fi

    cached_state=idle
    if output=$(timeout 5 hdparm -C "$dev" 2>&1); then
        lower=$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')
        if grep -q "sleeping" <<< "$lower"; then
            cached_state=deep_sleep
        elif grep -q "standby" <<< "$lower"; then
            cached_state=standby
        fi
    fi
    printf '%s|%s\n' "$now" "$cached_state" > "${file}.tmp.$$"
    mv "${file}.tmp.$$" "$file"
    printf '%s\n' "$cached_state"
}

disk_detect_sample() {
    local dev="$1" idle_seconds="${2:-8}" probe_interval="${3:-60}"
    local sample read_kbps write_kbps total_kbps active state
    [[ -b "$dev" ]] || { echo "offline|0|0|0"; return; }

    sample=$(disk_sample_io "$dev" "$idle_seconds")
    IFS='|' read -r read_kbps write_kbps total_kbps active <<< "$sample"
    if [[ "$active" == "1" ]]; then
        state=active
        printf '%s|idle\n' "$(date +%s)" > "$(disk_power_cache_path "$dev")"
    else
        state=$(disk_power_state_cached "$dev" "$probe_interval")
    fi
    printf '%s|%s|%s|%s\n' "$state" "${read_kbps:-0}" "${write_kbps:-0}" "${total_kbps:-0}"
}
