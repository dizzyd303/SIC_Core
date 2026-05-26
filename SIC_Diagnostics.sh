#!/bin/bash
#===============================================================================
# SIC_Diagnostics.sh — Scarface Intelligence Core | Vehicle Diagnostics Module
#
# Usage:
#   ./SIC_Diagnostics.sh "read diagnostic codes from vehicle"
#   ./SIC_Diagnostics.sh "check engine sensor data"
#   ./SIC_Diagnostics.sh "analyze recent system failures"
#
# Part of: SIC_Security | SIC_Skip | SIC_Diagnostics | SIC_COPE
#===============================================================================

SIC_CORE="$(cd "$(dirname "$0")" && pwd)/sic_core.sh"
[[ ! -f "$SIC_CORE" ]] && SIC_CORE="/usr/local/lib/sic_core.sh"
source "$SIC_CORE"
sic_check_version 1 3

sic_register_module \
    --name "SIC_Diagnostics" \
    --tools "python3, sensors, hddtemp, smartctl, lshw, dmidecode, dmesg, journalctl, ps, top, df, free, uptime, lscpu, lsblk, iostat, vmstat" \
    --danger 'rm -rf /|mkfs|dd of=/dev/sd|nc -e /bin|bash -i >|sh -i >|chmod 777 /|>/dev/sda' \
    --plan \
        "1. Read diagnostic trouble codes from vehicle OBD-II system" \
        "2. Check sensor data and engine parameters" \
        "3. Analyze system logs for recent failures or warnings" \
        "4. Generate diagnostic summary report"

# ─────────────────────────────────────────
# sic_run_module_suite() — Diagnostics checks
# ─────────────────────────────────────────
sic_run_module_suite() {
    local target="$1" tmp_dir="$2" visa_cfg="$3"
    sic_parse_visa_cfg "$visa_cfg"

    echo ""
    echo -e "${PURPLE}🔧 DIAGNOSTICS: Analyzing system/vehicle state...${NC}"
    mkdir -p "$tmp_dir/vuln"

    # [1/4] System health basics
    echo -e "${CYAN}  [1/4] System health check...${NC}"
    { echo "=== UPTIME ==="; uptime
      echo "=== MEMORY ==="; free -h
      echo "=== DISK ===";   df -h | head -20
      echo "=== CPU ===";    lscpu 2>/dev/null | head -20 || echo "lscpu not available"
    } > "$tmp_dir/vuln/system_health.txt"
    echo -e "${GREEN}     System health baseline saved${NC}"

    # [2/4] Sensor data
    echo -e "${CYAN}  [2/4] Sensor data collection...${NC}"
    if command -v sensors &>/dev/null; then
        sensors > "$tmp_dir/vuln/sensors.txt" 2>/dev/null || true
        echo -e "${GREEN}     Sensor data collected${NC}"
    else
        echo "lm-sensors not installed" > "$tmp_dir/vuln/sensors.txt"
    fi

    # [3/4] Log analysis
    echo -e "${CYAN}  [3/4] Recent system log analysis...${NC}"
    if command -v journalctl &>/dev/null; then
        journalctl -p err --since "24 hours ago" --no-pager \
            > "$tmp_dir/vuln/errors_last_24h.txt" 2>/dev/null || true
        echo -e "${GREEN}     $(wc -l < "$tmp_dir/vuln/errors_last_24h.txt") errors in last 24h${NC}"
    else
        echo "journalctl not available" > "$tmp_dir/vuln/errors_last_24h.txt"
    fi
    if command -v dmesg &>/dev/null; then
        dmesg | tail -50 > "$tmp_dir/vuln/dmesg_tail.txt" 2>/dev/null || true
    fi

    # [4/4] AI diagnostic summary
    echo -e "${CYAN}  [4/4] AI diagnostic analysis...${NC}"
    { echo "=== SYSTEM HEALTH ==="; cat "$tmp_dir/vuln/system_health.txt" 2>/dev/null
      echo "=== SENSORS ===";       cat "$tmp_dir/vuln/sensors.txt" 2>/dev/null | head -30
      echo "=== RECENT ERRORS ==="; head -40 "$tmp_dir/vuln/errors_last_24h.txt" 2>/dev/null
      echo "=== DMESG ===";         head -30 "$tmp_dir/vuln/dmesg_tail.txt" 2>/dev/null
    } > "$tmp_dir/vuln/diag_collated.txt"

    cat > "$tmp_dir/threat_prompt.txt" <<PROMPT
You are an automotive diagnostic technician reviewing system data.

Provide:
1. Critical issues detected (hardware failures, error codes)
2. System health assessment (CPU, memory, disk, thermal)
3. Recommended repairs or maintenance actions
4. Priority order for addressing findings

Be concise and professional. No reasoning preamble.

Diagnostic Data:
$(cat "$tmp_dir/vuln/diag_collated.txt")
PROMPT

    sic_llm_call "$THREAT_MODEL" "$tmp_dir/threat_prompt.txt" \
        "$tmp_dir/vuln/threat_analysis.txt" 120 || true

    echo -e "${BLUE}--- DIAGNOSTIC PREVIEW ---${NC}"
    head -20 "$tmp_dir/vuln/threat_analysis.txt"
    echo -e "${BLUE}--------------------------${NC}"
}

sic_run "$@"

