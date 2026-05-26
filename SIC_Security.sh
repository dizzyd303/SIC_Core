#!/bin/bash
#===============================================================================
# SIC_Security.sh — Scarface Intelligence Core | Security Assessment Module
# Created by SpYdA573 (Daniel Young)
# Usage:
#   ./SIC_Security.sh "recon example.com for open ports and vulns"
#   VISA_MODE=1 H1_USERNAME=spyda573 ./SIC_Security.sh "scan visa.com"
#   AUTO_RUN=1 ./SIC_Security.sh "scan 192.168.1.1"
#
# Part of: SIC_Security | SIC_Skip | SIC_Diagnostics | SIC_COPE
#===============================================================================

SIC_CORE="$(cd "$(dirname "$0")" && pwd)/sic_core.sh"
[[ ! -f "$SIC_CORE" ]] && SIC_CORE="/usr/local/lib/sic_core.sh"
source "$SIC_CORE"
sic_check_version 1 3

sic_register_module \
    --name "SIC_Security" \
    --tools "nmap, whatweb, nuclei, ffuf, gobuster, nikto, sqlmap, curl, dig, whois, theHarvester, testssl, searchsploit, arp-scan, arping, wget" \
    --danger 'rm -rf /|mkfs|dd of=/dev/sd|nc -e /bin|bash -i >|sh -i >|chmod 777 /|wget.*\| *bash|curl.*\| *bash|>/dev/sda' \
    --plan \
        "1. Scan target for open ports and running services using nmap" \
        "2. Perform web technology fingerprinting using whatweb" \
        "3. Run vulnerability detection against discovered services using nuclei"

# ─────────────────────────────────────────
# sic_run_module_suite() — Security recon suite
# ─────────────────────────────────────────
sic_run_module_suite() {
    local target="$1" tmp_dir="$2" visa_cfg="$3"
    sic_parse_visa_cfg "$visa_cfg"

    echo ""
    echo -e "${PURPLE}🔬 PROFESSIONAL RECON: $target${NC}"
    mkdir -p "$tmp_dir/vuln"

    if ! [[ "$target" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$ ]] && \
       ! [[ "$target" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${YELLOW}  [!] Target '$target' is not a valid IP or domain. Skipping.${NC}"
        return
    fi

    # Detect if target is a CIDR range (vs single host)
    local is_cidr=0
    [[ "$target" =~ /[0-9]+$ ]] && is_cidr=1

    # [1/6] Nmap
    echo -e "${CYAN}  [1/6] Port & service scan (nmap)...${NC}"
    local nmap_cmd="nmap"
    timeout 2 sudo -n true 2>/dev/null && nmap_cmd="sudo nmap"
    if [[ "$is_cidr" -eq 1 ]]; then
        # For CIDR: first do host discovery, then scan only live hosts with top 100 ports
        $nmap_cmd -sn -T4 "$target" -oG "$tmp_dir/vuln/hosts.gnmap" 2>/dev/null || true
        local live_count
        live_count=$(grep -c 'Status: Up' "$tmp_dir/vuln/hosts.gnmap" 2>/dev/null || echo "0")
        echo -e "${GREEN}     Live hosts: $live_count${NC}"
        if [[ "$live_count" -gt 0 ]]; then
            grep 'Status: Up' "$tmp_dir/vuln/hosts.gnmap" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
                > "$tmp_dir/vuln/live_hosts.txt" 2>/dev/null || true
            if [[ -s "$tmp_dir/vuln/live_hosts.txt" ]]; then
                $nmap_cmd -Pn -T2 $SIC_NMAP_RATE --top-ports 100 -sV \
                    -iL "$tmp_dir/vuln/live_hosts.txt" \
                    -oN "$tmp_dir/vuln/nmap.txt" -oX "$tmp_dir/vuln/nmap.xml" 2>/dev/null || true
            fi
        else
            echo "No live hosts discovered — scanning original target directly" >> "$tmp_dir/vuln/nmap.txt"
            $nmap_cmd -Pn -T2 $SIC_NMAP_RATE --top-ports 100 -sV "$target" \
                -oN "$tmp_dir/vuln/nmap.txt" -oX "$tmp_dir/vuln/nmap.xml" 2>/dev/null || true
        fi
    else
        $nmap_cmd -Pn -T2 $SIC_NMAP_RATE --top-ports 1000 -sV -sC \
            -oN "$tmp_dir/vuln/nmap.txt" -oX "$tmp_dir/vuln/nmap.xml" "$target" 2>&1 || true
    fi

    local open_ports
    open_ports=$(grep -E '^[0-9]+/tcp.*open' "$tmp_dir/vuln/nmap.txt" \
        | awk -F/ '{print $1}' | tr '\n' ',' | sed 's/,$//' || echo "")
    echo -e "${GREEN}     Open ports: ${open_ports:-none detected}${NC}"

    # For CIDR ranges, skip web-specific tools (whatweb, ffuf, nuclei, testssl)
    if [[ "$is_cidr" -eq 1 ]]; then
        echo -e "${YELLOW}  [!] Target is CIDR range — web tools skipped. Use single-IP for deep scan.${NC}"
        echo "Skipped: whatweb, testssl, ffuf, nuclei (CIDR range)" > "$tmp_dir/vuln/whatweb.txt"
        echo "Skipped: CIDR range" > "$tmp_dir/vuln/testssl.log"
        echo "Skipped: CIDR range" > "$tmp_dir/vuln/ffuf_https.json"
        echo "Skipped: CIDR range" > "$tmp_dir/vuln/nuclei.txt"
    else
        # [2/6] Whatweb
        echo -e "${CYAN}  [2/6] Web fingerprinting (whatweb)...${NC}"
        if command -v whatweb &>/dev/null; then
            local header_args=()
            [[ -n "${H1_USERNAME:-}" ]] && header_args=(--header "X-Hackerone: ${H1_USERNAME}")
            whatweb -a 3 $SIC_WHATWEB_WAIT "${header_args[@]}" "$target" \
                > "$tmp_dir/vuln/whatweb.txt" 2>/dev/null || true
        else
            echo "whatweb not installed" > "$tmp_dir/vuln/whatweb.txt"
        fi

        # [3/6] testssl
        echo -e "${CYAN}  [3/6] SSL/TLS analysis (testssl)...${NC}"
        if echo "$open_ports" | grep -q '\b443\b'; then
            local testssl_bin; testssl_bin=$(command -v testssl || command -v testssl.sh || echo "")
            if [[ -n "$testssl_bin" ]]; then
                $testssl_bin --quiet --warnings batch --severity HIGH \
                    --logfile "$tmp_dir/vuln/testssl.log" "$target" > /dev/null 2>&1 || true
            else
                echo "testssl not installed" > "$tmp_dir/vuln/testssl.log"
            fi
        else
            echo "Port 443 not open — skipping testssl" > "$tmp_dir/vuln/testssl.log"
        fi

        # [4/6] ffuf
        echo -e "${CYAN}  [4/6] Directory discovery (ffuf)...${NC}"
        if echo "$open_ports" | grep -qE '\b(80|443)\b' && command -v ffuf &>/dev/null; then
            local wordlist=""
            for wl in /usr/share/wordlists/dirb/common.txt \
                       /usr/share/dirb/wordlists/common.txt \
                       /usr/share/seclists/Discovery/Web-Content/common.txt; do
                [[ -f "$wl" ]] && wordlist="$wl" && break
            done
            if [[ -n "$wordlist" ]]; then
                for scheme in https http; do
                    ffuf -u "${scheme}://${target}/FUZZ" -w "$wordlist" \
                        -mc 200,204,301,302,403 -t 20 -s \
                        -o "$tmp_dir/vuln/ffuf_${scheme}.json" -of json 2>/dev/null || true
                done
            else
                echo "No wordlist found" > "$tmp_dir/vuln/ffuf_https.json"
            fi
        else
            echo "No web ports open or ffuf not installed" > "$tmp_dir/vuln/ffuf_https.json"
        fi

        # [5/6] Nuclei
        echo -e "${CYAN}  [5/6] Vulnerability scan (nuclei)...${NC}"
        if command -v nuclei &>/dev/null; then
            local nuclei_templates=""
            # Try known template directories
            for td in /home/spyda573/.local/nuclei-templates ~/nuclei-templates /opt/nuclei-templates; do
                if [[ -d "$td" ]] && ls "$td"/*.yaml &>/dev/null 2>/dev/null; then
                    nuclei_templates="$td"; break
                fi
            done
            timeout 90 nuclei -u "$target" -severity critical,high,medium -silent \
                ${nuclei_templates:+-t "$nuclei_templates"} \
                $SIC_NUCLEI_RATE -timeout 10 -o "$tmp_dir/vuln/nuclei.txt" 2>/dev/null || true
            local nuclei_count; nuclei_count=$(wc -l < "$tmp_dir/vuln/nuclei.txt" 2>/dev/null || echo "0")
            if [[ "$nuclei_count" -gt 0 ]]; then
                echo -e "${RED}  ⚠  $nuclei_count findings${NC}"
            else
                echo -e "${GREEN}  No nuclei findings${NC}"
            fi
        else
            echo "nuclei not installed" > "$tmp_dir/vuln/nuclei.txt"
        fi
    fi

    # [6/6] AI Threat Analysis
    echo -e "${CYAN}  [6/6] AI threat analysis...${NC}"
    { echo "=== NMAP ==="; head -60 "$tmp_dir/vuln/nmap.txt" 2>/dev/null
      echo "=== NUCLEI ==="; cat "$tmp_dir/vuln/nuclei.txt" 2>/dev/null | head -40
      echo "=== WHATWEB ==="; cat "$tmp_dir/vuln/whatweb.txt" 2>/dev/null | head -15
      echo "=== TESTSSL ==="; head -20 "$tmp_dir/vuln/testssl.log" 2>/dev/null
    } > "$tmp_dir/vuln/scan_collated.txt"

    cat > "$tmp_dir/threat_prompt.txt" <<PROMPT
You are a senior penetration tester writing a structured threat analysis.
Review the scan results below for target: ${target}

Provide:
1. Critical findings (with CVE numbers where applicable)
2. Attack surface summary
3. Prioritized exploitation paths
4. Recommended mitigations

Be concise and professional. No reasoning preamble.

Scan Results:
$(cat "$tmp_dir/vuln/scan_collated.txt")
PROMPT

    if sic_llm_call "$THREAT_MODEL" "$tmp_dir/threat_prompt.txt" \
            "$tmp_dir/vuln/threat_analysis.txt" 120; then
        echo -e "${GREEN}  ✅ Threat analysis complete${NC}"
    else
        echo "Threat analysis unavailable (model timeout)" > "$tmp_dir/vuln/threat_analysis.txt"
        echo -e "${YELLOW}  ⚠  Threat model failed — placeholder written${NC}"
    fi

    echo -e "${BLUE}--- THREAT ANALYSIS PREVIEW ---${NC}"
    head -25 "$tmp_dir/vuln/threat_analysis.txt"
    echo -e "${BLUE}-------------------------------${NC}"
}

# Standalone commands
if [[ "$1" == "whois" ]]; then
    whois_lookup "$2"
    exit $?
fi

if [[ "$1" == "dns" ]]; then
    dns_lookup "$2" "$3"
    exit $?
fi

sic_run "$@"



