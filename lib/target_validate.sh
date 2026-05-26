#!/usr/bin/env bash
# lib/target_validate.sh

validate_target() {
    local tgt="$1"

    # IPv4 — validate each octet is 0-255
    if [[ $tgt =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local valid=1
        for octet in "${BASH_REMATCH[@]:1}"; do
            [[ "$octet" -gt 255 ]] && valid=0 && break
        done
        [[ $valid -eq 1 ]] && echo "ipv4" && return 0
    fi

    # CIDR — validate IP portion + prefix length
    if [[ $tgt =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
        echo "cidr" && return 0
    fi

    # Domain — standard regex
    if [[ $tgt =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        echo "domain" && return 0
    fi

    # IPv6 — basic format check
    if [[ $tgt =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]]; then
        echo "ipv6" && return 0
    fi

    echo "invalid" >&2
    return 1
}
