#!/bin/bash

settings_init() {
    local file="$1" default_file="${2:-}"
    if [[ ! -f "$file" ]]; then
        mkdir -p "$(dirname "$file")"
        if [[ -n "$default_file" && -f "$default_file" ]]; then
            cp "$default_file" "$file"
        else
            printf '[mode]\nglobal=smart\n\n[disk_map]\n' > "$file"
        fi
    fi
}

settings_get() {
    local file="$1" section="$2" key="$3" fallback="${4:-}"
    local current="" value=""
    [[ -f "$file" ]] || { printf '%s\n' "$fallback"; return; }

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            current="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$current" == "$section" && "$line" =~ ^${key}=(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
    done < "$file"

    printf '%s\n' "${value:-$fallback}"
}

settings_set() {
    local file="$1" section="$2" key="$3" value="$4"
    local tmp="${file}.new.$$" current="" in_section=0 found=0
    settings_init "$file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            if [[ $in_section -eq 1 && $found -eq 0 ]]; then
                printf '%s=%s\n' "$key" "$value"
                found=1
            fi
            current="${BASH_REMATCH[1]}"
            [[ "$current" == "$section" ]] && in_section=1 || in_section=0
            printf '%s\n' "$line"
            continue
        fi
        if [[ $in_section -eq 1 && "$line" =~ ^${key}= ]]; then
            printf '%s=%s\n' "$key" "$value"
            found=1
        else
            printf '%s\n' "$line"
        fi
    done < "$file" > "$tmp" || return 1

    if [[ $found -eq 0 && $in_section -eq 1 ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
        found=1
    fi

    if [[ $found -eq 0 ]]; then
        if ! grep -q "^\[${section}\]$" "$file" 2>/dev/null; then
            printf '\n[%s]\n' "$section" >> "$tmp"
        fi
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
    fi
    mv "$tmp" "$file"
}

settings_validate_rgb() {
    local value="$1" r g b extra
    read -r r g b extra <<< "$value"
    [[ -z "$extra" && "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || return 1
    (( r <= 255 && g <= 255 && b <= 255 ))
}
