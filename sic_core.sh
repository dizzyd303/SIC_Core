#!/bin/bash
#===============================================================================
# sic_core.sh — SIC (Scarface Intelligence Core) Shared Pipeline
# Version: 2.1.0
# Created by SpYdA573 (Daniel Young)
# Now includes built‑in API gateway and LM Studio backend.
#
# Sourced by SIC_Security, SIC_Skip, SIC_Diagnostics, SIC_COPE, Heartland modules.
#===============================================================================

# ── Guard: prevent double-sourcing ──
if [[ -n "${SIC_CORE_LOADED:-}" ]]; then return 0; fi
SIC_CORE_LOADED="1"

set -euo pipefail
IFS=$'\n\t'

# ── Shell depth guard ──
if [[ "${BASH_SUBSHELL:-0}" -gt 10 ]] || [[ "${SHLVL:-0}" -gt 6 ]]; then
    echo "[!] CRITICAL: Shell depth exceeded (SHLVL=${SHLVL:-0}). Aborting." >&2
    exit 99
fi

# ── Ollama tuning for limited hardware ──
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_MAX_LOADED_MODELS=2

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── Persistence: SIC home directory ──
SIC_HOME="${SIC_HOME:-${HOME}/.sic}"
SIC_RUNS_DIR="${SIC_HOME}/runs"
SIC_INDEX="${SIC_HOME}/runs.index"
mkdir -p "${SIC_RUNS_DIR}"
touch "${SIC_INDEX}"

# ── Default model assignments (can be overridden by environment) ──
# Using CPU‑friendly models: LM Studio for architect/report, Ollama for coder/enhancer
ARCHITECT_MODEL="${ARCHITECT_MODEL:-lfm2}"
CODER_MODEL="${CODER_MODEL:-qwen2.5-coder:7b}"
ENHANCER_MODEL="${ENHANCER_MODEL:-sec-coder:latest}"
THREAT_MODEL="${THREAT_MODEL:-paramhshah19gpt/claudecode1:latest}"
REPORT_MODEL="${REPORT_MODEL:-llama}"

# ── Default settings ──
SIC_MODULE_NAME=""
SIC_TOOL_WHITELIST=""
SIC_DANGEROUS_PATTERNS='rm -rf /|mkfs|dd of=/dev/sd|nc -e /bin|bash -i >|sh -i >|chmod 777 /|wget.*\| *bash|curl.*\| *bash|>/dev/sda'
SIC_DEFAULT_PLAN=()

# ─────────────────────────────────────────
# API Gateway: Load keys and define functions
# ─────────────────────────────────────────
CONFIG_DIR="${HOME}/.config/sic"
CONFIG_FILE="${CONFIG_DIR}/api_keys.env"

# Default keys (testing only – will be overridden by file if present)
APILAYER_KEY="${APILAYER_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"
SCRAPERAPI_KEY="${SCRAPERAPI_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"
PDF_LAYER_KEY="${PDF_LAYER_KEY:-5ed234b08c754d98598cc93016534002}"
EXCHANGE_RATES_KEY="${EXCHANGE_RATES_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"
COINLAYER_KEY="${COINLAYER_KEY:-49c89fe9b1568136827581a5127c4e97}"
MARKETSTACK_KEY="${MARKETSTACK_KEY:-534f4bd1cbc6e49c09c70ff7f29dd0b5}"
IPAPI_KEY="${IPAPI_KEY:-2458480825856c424514bdb09052677d}"
AVIATIONSTACK_KEY="${AVIATIONSTACK_KEY:-026bebb4a558f722ea051addf8fa6184}"
MASTER_KEY="${MASTER_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"
DOMAIN_DISCOVERY_KEY="${DOMAIN_DISCOVERY_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"
EMAIL_VERIFY_KEY="${EMAIL_VERIFY_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"
NUMBER_VERIFY_KEY="${NUMBER_VERIFY_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"
IBAN_KEY="${IBAN_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"
USERAGENT_KEY="${USERAGENT_KEY:-eNrbMx5xb1Wd1BL9qhmFRHsUNA2IOKe2}"

# Load user config if present
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Helper: low-level API request
_api_request() {
    local url="$1"
    local auth_header="$2"
    local method="${3:-GET}"
    local data="${4:-}"

    local curl_cmd="curl -s -X $method"
    [[ -n "$auth_header" ]] && curl_cmd+=" -H '$auth_header'"
    if [[ -n "$data" ]]; then
        curl_cmd+=" -H 'Content-Type: application/json' -d '$data'"
    fi
    curl_cmd+=" '$url'"

    local response
    response=$(eval $curl_cmd 2>/dev/null || echo '{"error":"request_failed"}')
    echo "$response"
}

# ----------------------------------------------------------------------
# Public API Functions (available to any module)
# ----------------------------------------------------------------------

# Domain & DNS
whois_lookup() {
    local domain="$1"
    local url="https://api.apilayer.com/whois/query?domain=$domain"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

dns_lookup() {
    local domain="$1"
    local record_type="${2:-A}"
    local url="https://api.apilayer.com/dns/lookup/$record_type/$domain"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

domain_discovery() {
    local domain="$1"
    local url="https://api.apilayer.com/domain_discovery/search?domain=$domain"
    _api_request "$url" "apikey: $DOMAIN_DISCOVERY_KEY"
}

# Search engines
google_search() {
    local query="$1"
    local num="${2:-10}"
    local url="https://api.apilayer.com/google/search?q=$(echo "$query" | sed 's/ /%20/g')&num=$num"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

bing_search() {
    local query="$1"
    local url="https://api.apilayer.com/bing/search?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

brave_search() {
    local query="$1"
    local url="https://api.apilayer.com/brave/search?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

google_images() {
    local query="$1"
    local url="https://api.apilayer.com/google/images?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

google_maps() {
    local query="$1"
    local url="https://api.apilayer.com/google/maps?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

google_news() {
    local query="$1"
    local url="https://api.apilayer.com/google/news?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

google_shopping() {
    local query="$1"
    local url="https://api.apilayer.com/google/shopping?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

google_videos() {
    local query="$1"
    local url="https://api.apilayer.com/google/videos?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# Location & IP
ip_to_geo() {
    local ip="$1"
    local url="https://api.apilayer.com/ip_to_location/$ip"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

ipapi_lookup() {
    local ip="$1"
    curl -s "https://ipapi.co/$ip/json/"
}

# Verification APIs
email_verify() {
    local email="$1"
    local url="https://api.apilayer.com/email_verification/check?email=$email"
    _api_request "$url" "apikey: $EMAIL_VERIFY_KEY"
}

phone_verify() {
    local number="$1"
    local url="https://api.apilayer.com/number_verification/validate?number=$number"
    _api_request "$url" "apikey: $NUMBER_VERIFY_KEY"
}

iban_validate() {
    local iban="$1"
    local url="https://api.apilayer.com/iban/validate?iban=$iban"
    _api_request "$url" "apikey: $IBAN_KEY"
}

# PDF Generation
pdf_generate() {
    local html_content="$1"
    local output_file="$2"
    local response
    response=$(curl -s -X POST "https://api.pdflayer.com/api/convert" \
        -H "Content-Type: application/json" \
        -d "{\"document_html\": \"$html_content\", \"api_key\": \"$PDF_LAYER_KEY\"}")
    if [[ -n "$output_file" ]]; then
        echo "$response" | base64 -d > "$output_file"
        echo "PDF saved to $output_file"
    else
        echo "$response"
    fi
}

# Scraper API
scrape_url() {
    local url="$1"
    local api_url="http://api.scraperapi.com?api_key=$SCRAPERAPI_KEY&url=$(echo "$url" | sed 's/ /%20/g')"
    curl -s "$api_url"
}

# User agent
random_user_agent() {
    curl -s "https://api.apilayer.com/user_agent" -H "apikey: $USERAGENT_KEY"
}

# Financial & market
exchange_rates() {
    local base="${1:-USD}"
    curl -s "https://api.apilayer.com/exchangerates_data/latest?base=$base" \
        -H "apikey: $EXCHANGE_RATES_KEY"
}

market_stack() {
    local symbol="$1"
    curl -s "http://api.marketstack.com/v1/eod?access_key=$MARKETSTACK_KEY&symbols=$symbol"
}

coinlayer() {
    local symbol="$1"
    curl -s "http://api.coinlayer.com/live?access_key=$COINLAYER_KEY&symbols=$symbol"
}

# Aviation
aviation_flight() {
    local flight_number="$1"
    curl -s "http://api.aviationstack.com/v1/flights?access_key=$AVIATIONSTACK_KEY&flight_number=$flight_number"
}

# ----------------------------------------------------------------------
# SIC Core Functions
# ----------------------------------------------------------------------

sic_register_module() {
    local name="" tools="" danger=""
    local -a plan=()
    local skip_coder=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)       name="$2";       shift 2 ;;
            --tools)      tools="$2";      shift 2 ;;
            --danger)     danger="$2";     shift 2 ;;
            --skip-coder) skip_coder=1;    shift ;;
            --plan)       shift; while [[ $# -gt 0 ]] && ! [[ "$1" =~ ^-- ]]; do
                              plan+=("$1"); shift
                           done ;;
            *)            echo "sic_register_module: unknown option $1" >&2; return 1 ;;
        esac
    done
    SIC_MODULE_NAME="$name"
    SIC_TOOL_WHITELIST="$tools"
    [[ -n "$danger" ]] && SIC_DANGEROUS_PATTERNS="$danger"
    SIC_SKIP_CODER=$skip_coder
    if [[ ${#plan[@]} -eq 0 ]]; then
        SIC_DEFAULT_PLAN=(
            "1. Scan target for open ports and running services"
            "2. Perform technology fingerprinting"
            "3. Run vulnerability or issue detection"
            "4. Generate a report of findings"
        )
    else
        SIC_DEFAULT_PLAN=("${plan[@]}")
    fi
}

strip_think() {
    python3 - "$1" <<'PYEOF'
import sys, re
with open(sys.argv[1], 'r', errors='replace') as f:
    text = f.read()
text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL | re.IGNORECASE)
text = re.sub(r'(?m)^.*?Thinking\.\.\..*$\n?', '', text)
text = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', text)
text = re.sub(r'[\u2580-\u259F\u2800-\u28FF]', '', text)
text = re.sub(r'[^\S\n\t ]+', ' ', text)
text = re.sub(r'\n{3,}', '\n\n', text)
print(text.strip())
PYEOF
}

sic_llm_call() {
    local model="$1"
    local prompt_file="$2"
    local output_file="$3"
    local timeout_secs="${4:-120}"
    local raw_file="${output_file}.raw"

    local prompt_text
    prompt_text=$(cat "$prompt_file" 2>/dev/null || true)
    if [[ -z "$prompt_text" ]]; then
        echo "[EMPTY PROMPT]" > "$output_file"
        return 1
    fi

    # 1) Try `llm` CLI
    if command -v llm &>/dev/null; then
        set +e
        timeout "${timeout_secs}" llm -m "$model" "$prompt_text" > "$raw_file" 2>&1
        local exit_code=$?
        set -e
    # 2) Try Ollama
    elif command -v ollama &>/dev/null; then
        set +e
        timeout "${timeout_secs}" ollama run "$model" "$prompt_text" > "$raw_file" 2>&1
        local exit_code=$?
        set -e
    # 3) Try LM Studio (port 1234)
    elif curl -sf "http://localhost:1234/v1/models" >/dev/null 2>&1; then
        set +e
        timeout "${timeout_secs}" python3 - "$model" "$prompt_file" <<'PYEOF' > "$raw_file" 2>&1
import json, urllib.request, sys
with open(sys.argv[2]) as f:
    prompt = f.read()
payload = json.dumps({
    'model': 'local-model',   # LM Studio ignores model name, uses what's loaded
    'messages': [{'role': 'user', 'content': prompt}],
    'max_tokens': 2048,
    'temperature': 0.3
}).encode()
req = urllib.request.Request(
    'http://localhost:1234/v1/chat/completions',
    data=payload,
    headers={'Content-Type': 'application/json'}
)
try:
    resp = json.loads(urllib.request.urlopen(req).read())
    sys.stdout.write(resp['choices'][0]['message']['content'])
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
PYEOF
        local exit_code=$?
        set -e
    # 4) Try Unsloth / other OpenAI server on port 8000
    elif curl -sf "http://localhost:8000/v1/models" >/dev/null 2>&1; then
        set +e
        timeout "${timeout_secs}" python3 - "$model" "$prompt_file" <<'PYEOF' > "$raw_file" 2>&1
import json, urllib.request, sys
model = sys.argv[1]
with open(sys.argv[2]) as f:
    prompt = f.read()
payload = json.dumps({
    'model': model,
    'messages': [{'role': 'user', 'content': prompt}],
    'max_tokens': 2048,
    'temperature': 0.3
}).encode()
req = urllib.request.Request(
    'http://localhost:8000/v1/chat/completions',
    data=payload,
    headers={'Content-Type': 'application/json'}
)
try:
    resp = json.loads(urllib.request.urlopen(req).read())
    sys.stdout.write(resp['choices'][0]['message']['content'])
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
PYEOF
        local exit_code=$?
        set -e
    else
        echo "[ERROR] No LLM backend available (llm/ollama/lmstudio/unsloth)" > "$output_file"
        return 1
    fi

    if [[ $exit_code -eq 124 ]]; then
        echo "[TIMEOUT after ${timeout_secs}s]" > "$output_file"
        return 1
    fi
    if [[ ! -s "$raw_file" ]]; then
        echo "[EMPTY RESPONSE]" > "$output_file"
        return 1
    fi

    strip_think "$raw_file" > "$output_file"
    rm -f "$raw_file"
    return 0
}

sic_extract_target() {
    local goal="$1"
    local target
    target=$(echo "$goal" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?' | head -1 || true)
    if [[ -z "$target" ]]; then
        target=$(echo "$goal" | grep -oE '[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1 || true)
    fi
    if [[ -z "$target" ]]; then
        target=$(echo "$goal" | grep -oiE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -1 || true)
    fi
    if [[ -z "$target" ]]; then
        target=$(echo "$goal" | sed -n 's/.*for \([A-Za-z][A-Za-z ]\{1,50\}\)[,.]*.*/\1/p' | head -1 || true)
        if [[ -n "$target" ]]; then
            target=$(echo "$target" | sed 's/\s*Age\s*$//I; s/\s*Location\s*$//I' | xargs)
        fi
    fi
    if [[ -z "$target" ]]; then
        if echo "$goal" | grep -qiE '(find|search|lookup|locate|skip.?trace|osint).*(for|on)'; then
            target=$(echo "$goal" | grep -oiE '[A-Z][a-z]+ [A-Z][a-z]+' | head -1 || true)
        fi
    fi
    echo "${target:-target_not_specified}"
}

sic_extract_pcap() {
    echo "$1" | grep -oE '[^ ]+\.(pcap|pcapng)' | head -1 || true
}

sic_run() {
    local goal="${1:-}"
    if [[ -z "$goal" ]]; then
        echo "Usage: $0 \"Your high-level goal\""
        exit 1
    fi

    local run_ts; run_ts=$(date '+%Y%m%d_%H%M%S')
    local run_id="${SIC_MODULE_NAME}_${run_ts}_$$"
    local tmp_dir="${SIC_RUNS_DIR}/${run_id}"
    mkdir -p "$tmp_dir"/{outputs,vuln,scripts}

    local script_self; script_self="$(basename "$0")"
    local target_hash; target_hash=$(echo "${goal}" | md5sum | cut -c1-8)
    local lock_file="/tmp/sic_${script_self%.*}_${target_hash}.lock"
    if [[ -f "$lock_file" ]]; then
        local lock_pid; lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            echo "[!] Already running this target (PID $lock_pid). Exiting." >&2
            exit 1
        fi
        rm -f "$lock_file"
    fi
    echo "$$" > "$lock_file"
    trap '[[ -n "${lock_file:-}" ]] && rm -f "${lock_file}"' EXIT INT TERM

    local visa_mode="${VISA_MODE:-0}"
    local h1_username="${H1_USERNAME:-}"
    local auto_run="${AUTO_RUN:-0}"

    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║  ${SIC_MODULE_NAME} — Pipeline v2.1            ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"

    local target; target=$(sic_extract_target "$goal")
    local pcap_file; pcap_file=$(sic_extract_pcap "$goal")

    export SIC_GOAL="$goal"
    export SIC_TARGET="$target"
    export SIC_RUN_ID="$run_id"
    export SIC_RUN_DIR="$tmp_dir"

    echo "${run_id}|${SIC_MODULE_NAME}|${target}|$(date '+%Y-%m-%d %H:%M:%S')|running|${goal}" >> "${SIC_INDEX}"

    if echo "$target" | grep -qE '/[0-9]+$'; then
        local cidr_bits; cidr_bits=$(echo "$target" | grep -oE '/[0-9]+' | tr -d '/')
        local host_count=$(( 1 << (32 - cidr_bits) ))
        if [[ $host_count -gt 65536 ]]; then
            echo -e "${YELLOW}⚠  WARNING: Target ${target} covers ${host_count} hosts.${NC}"
            export SIC_LARGE_CIDR=1
        fi
    fi

    local nmap_rate="" nuclei_rate="" whatweb_wait=""
    if [[ "$visa_mode" == "1" ]]; then
        if [[ -z "$h1_username" ]]; then
            echo -e "${RED}[!] VISA_MODE=1 requires H1_USERNAME to be set.${NC}" >&2
            rm -f "$lock_file"; exit 1
        fi
        nmap_rate="--max-rate=1"
        nuclei_rate="-rate-limit 1 -bulk-size 1"
        whatweb_wait="--wait 1"
        echo -e "${PURPLE}[VISA] Compliance active — H1: $h1_username | 1 req/sec${NC}"
    else
        nmap_rate="--max-rate=100"
        nuclei_rate=""
        whatweb_wait=""
    fi

    if [[ -n "$pcap_file" ]]; then
        if [[ -f "$pcap_file" ]]; then
            echo -e "${PURPLE}📦 PCAP detected: $pcap_file${NC}"
            echo -e "${YELLOW}[!] PCAP analysis not yet implemented — skipping.${NC}"
        else
            echo -e "${RED}[!] PCAP file not found: $pcap_file${NC}" >&2
        fi
    fi

    SIC_GOAL_TYPE="domain"
    if ! echo "$goal" | grep -qiE '([0-9]{1,3}\.){3}[0-9]{1,3}|[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'; then
        SIC_GOAL_TYPE="personal"
    fi
    export SIC_GOAL_TYPE

    # STAGE 1: ARCHITECT
    echo -e "${BLUE}📐 ARCHITECT: Breaking down goal...${NC}"
    cat > "$tmp_dir/architect_prompt.txt" <<PROMPT
Goal: ${goal}
Goal type: ${SIC_GOAL_TYPE}
Whitelist: ${SIC_TOOL_WHITELIST}
Rules:
- Output 3-5 numbered phases like: 1. Do X\n2. Do Y
- One phase per line, start with "1. "
- Describe actions in plain English
- No install steps, no raw commands, no preamble
PROMPT

    local architect_ok=0
    if sic_llm_call "$ARCHITECT_MODEL" "$tmp_dir/architect_prompt.txt" "$tmp_dir/plan_raw.txt" 60; then
        grep -E '^[[:space:]]*[0-9]+[\.\)]' "$tmp_dir/plan_raw.txt" \
            | sed 's/^[[:space:]]*//; s/[)][[:space:]]*/. /' \
            > "$tmp_dir/plan.txt" 2>/dev/null || true
        [[ -s "$tmp_dir/plan.txt" ]] && architect_ok=1
    fi

    if [[ "$architect_ok" -eq 0 ]]; then
        echo -e "${YELLOW}⚠  Architect failed — using default ${SIC_MODULE_NAME} plan.${NC}"
        printf '%s\n' "${SIC_DEFAULT_PLAN[@]}" > "$tmp_dir/plan.txt"
    fi

    echo -e "${GREEN}📋 PLAN:${NC}"
    cat "$tmp_dir/plan.txt"; echo ""

    # STAGE 2A: CODER (serial)
    echo -e "${YELLOW}🔧 CODER: Generating scripts...${NC}"
    local -a phase_plan=()
    while IFS= read -r line; do phase_plan+=("$line"); done < <(grep -E '^[0-9]+\.' "$tmp_dir/plan.txt")

    local phase_counter=0
    for phase in "${phase_plan[@]}"; do
        phase_counter=$(( phase_counter + 1 ))
        local script_path="$tmp_dir/scripts/phase_${phase_counter}.sh"

        echo -e "${CYAN}  Phase ${phase_counter}: ${phase}${NC}"

        if [[ "${SIC_SKIP_CODER:-0}" -eq 1 ]]; then
            cat > "$script_path" <<PLACEHOLDER
#!/bin/bash
set -euo pipefail
echo "Phase ${phase_counter}: ${phase} (handled by module suite)"
PLACEHOLDER
            chmod +x "$script_path"
            continue
        fi

        cat > "$tmp_dir/coder_prompt_${phase_counter}.txt" <<PROMPT
Write a bash script that performs this task: ${phase}
Target: ${target}
Requirements:
- Start with: #!/bin/bash
- Use: set -euo pipefail
- Set: TARGET="${target}"
- NEVER wrap lines at 80 columns
- Save output to files in current directory
- Include || true after tool commands
- Do NOT call ollama, llm, or reference this script's own filename
- Do NOT include markdown fences or explanations
- Output ONLY the raw bash script
PROMPT

        local raw="$tmp_dir/scripts/phase_${phase_counter}.raw"
        sic_llm_call "$CODER_MODEL" "$tmp_dir/coder_prompt_${phase_counter}.txt" "$raw" 120 2>/dev/null || true

        if [[ -s "$raw" ]] && grep -q '^#!/bin/bash' "$raw"; then
            awk '/^#!\/bin\/bash/{flag=1} flag' "$raw" > "$script_path"
            grep -v '^```' "$script_path" > "${script_path}.tmp" 2>/dev/null && mv "${script_path}.tmp" "$script_path"
            tr -d '\r' < "$script_path" > "${script_path}.tmp" 2>/dev/null && mv "${script_path}.tmp" "$script_path"
            if ! grep -q 'set -euo pipefail' "$script_path"; then
                { echo 'set -euo pipefail'; cat "$script_path"; } > "${script_path}.tmp" && mv "${script_path}.tmp" "$script_path"
            fi
            if ! bash -n "$script_path" 2>/dev/null; then
                echo -e "${RED}    X Phase ${phase_counter} syntax error - using fallback${NC}"
                cat > "$script_path" <<FALLOUT
#!/bin/bash
set -euo pipefail
TARGET="${target}"
echo "Phase ${phase_counter}: (network scan on \$TARGET)"
nmap -Pn -T2 ${nmap_rate} --top-ports 1000 -sV "\$TARGET" -oN "phase_${phase_counter}_nmap.txt" 2>&1 || true
FALLOUT
            fi
        else
            echo -e "${YELLOW}    - Phase ${phase_counter} coder failed, using fallback${NC}"
            cat > "$script_path" <<FALLOUT
#!/bin/bash
set -euo pipefail
TARGET="${target}"
echo "Phase ${phase_counter}: (network scan on \$TARGET)"
nmap -Pn -T2 ${nmap_rate} --top-ports 1000 -sV "\$TARGET" -oN "phase_${phase_counter}_nmap.txt" 2>&1 || true
FALLOUT
        fi

        chmod +x "$script_path"
        rm -f "$raw" "$tmp_dir/coder_prompt_${phase_counter}.txt"
    done

    echo -e "${GREEN}  ✓ All ${phase_counter} scripts generated${NC}"

    # STAGE 2B: ENHANCER (conditional)
    if echo "$goal" | grep -qiE 'exploit|bypass|inject|reverse.?shell|payload|pentest'; then
        echo -e "${PURPLE}🛡  ENHANCER: Adding exploit modules...${NC}"
        for script in "$tmp_dir/scripts"/phase_*.sh; do
            local phase_num; phase_num=$(basename "$script" .sh)
            local enhanced="$tmp_dir/scripts/${phase_num}.enhanced"
            cat > "$tmp_dir/enhance_prompt_${phase_num}.txt" <<PROMPT
You are a red-team tool enhancer. Add exploit checks, extra curl probes, and payload tests.
Output ONLY the complete enhanced bash script. Start with #!/bin/bash.
Goal context: ${goal}

Script to enhance:
$(cat "$script")
PROMPT

            if sic_llm_call "$ENHANCER_MODEL" "$tmp_dir/enhance_prompt_${phase_num}.txt" "$enhanced" 90; then
                if grep -q '^#!/bin/bash' "$enhanced" && bash -n "$enhanced" 2>/dev/null; then
                    mv "$enhanced" "$script"; chmod +x "$script"
                    echo -e "${GREEN}    ✓ $(basename "$script") enhanced${NC}"
                else
                    rm -f "$enhanced"
                fi
            else
                rm -f "$enhanced"
            fi
            rm -f "$tmp_dir/enhance_prompt_${phase_num}.txt"
        done
    fi

    # STAGE 3: REVIEWER
    echo -e "${CYAN}🔍 REVIEWER: Checking scripts for dangerous patterns...${NC}"
    local review_failed=0
    for script in "$tmp_dir/scripts"/phase_*.sh; do
        if grep -qiE "(ollama run|llm|$(basename "$0"))" "$script" 2>/dev/null; then
            echo -e "${RED}  ✗ $(basename "$script") contains recursive reference.${NC}"
            review_failed=1
        fi
        if grep -qE "$SIC_DANGEROUS_PATTERNS" "$script" 2>/dev/null; then
            echo -e "${RED}  ✗ $(basename "$script") contains prohibited command.${NC}"
            review_failed=1
        fi
    done
    if [[ "$review_failed" -eq 1 ]]; then
        echo -e "${RED}[!] REVIEWER: Safety check failed. Aborting.${NC}" >&2
        rm -f "$lock_file"; exit 1
    fi
    echo -e "${GREEN}  ✓ All scripts passed safety review${NC}"

    # STAGE 4: EXECUTE
    local confirm="n"
    if [[ "$auto_run" == "1" ]]; then confirm="y"
    else echo ""; echo -e "${BLUE}🚀 EXECUTE: Run generated scripts? (y/n)${NC}"; read -r confirm
    fi

    if [[ "$confirm" == "y" ]]; then
        for script in "$tmp_dir/scripts"/phase_*.sh; do
            local script_name; script_name=$(basename "$script")
            local log="$tmp_dir/outputs/${script_name%.sh}.log"
            echo -e "${YELLOW}▶ Running: $script_name${NC}"
            if timeout 300 bash "$script" 2>&1 | tee "$log"; then
                echo -e "${GREEN}   ✓ Completed${NC}"
            else local ec=$?
                [[ $ec -eq 124 ]] && echo -e "${YELLOW}   ⏱ Timed out after 5 min${NC}" || echo -e "${RED}   ✗ Failed (exit $ec)${NC}"
            fi
        done
        echo -e "${GREEN}✅ Execution complete${NC}"
    else echo -e "${YELLOW}⏭ Execution skipped. Scripts: $tmp_dir/scripts/${NC}"
    fi

    # STAGE 4B: MODULE SUITE (if defined)
    if [[ "$confirm" == "y" ]] && declare -f sic_run_module_suite > /dev/null; then
        sic_run_module_suite "$target" "$tmp_dir" "$nmap_rate" "$nuclei_rate" "$whatweb_wait"
    fi

    # STAGE 5: REPORT
    echo -e "${CYAN}📝 REPORT: Generating...${NC}"
    : > "$tmp_dir/all_outputs.txt"
    if ls "$tmp_dir/outputs"/*.log &>/dev/null 2>/dev/null; then
        cat "$tmp_dir/outputs"/*.log >> "$tmp_dir/all_outputs.txt" 2>/dev/null || true
    fi
    if [[ -f "$tmp_dir/vuln/scan_collated.txt" ]]; then
        cat "$tmp_dir/vuln/scan_collated.txt" >> "$tmp_dir/all_outputs.txt" 2>/dev/null || true
    fi
    if [[ ! -s "$tmp_dir/all_outputs.txt" ]]; then
        echo "[No execution logs produced]" > "$tmp_dir/all_outputs.txt"
    fi
    cat > "$tmp_dir/report_prompt.txt" <<PROMPT
Generate a professional ${SIC_MODULE_NAME} assessment report in markdown.
Do not include any reasoning, thinking, or preamble. Output only the report.

Goal: ${goal}
Target: ${target}
Plan:
$(cat "$tmp_dir/plan.txt")
Execution Logs:
$(head -80 "$tmp_dir/all_outputs.txt" 2>/dev/null || echo "N/A")

Use this exact structure:
# ${SIC_MODULE_NAME} Assessment Report
## Executive Summary
## Target Overview
## Phases Executed
## Findings
### Critical
### High
### Medium
### Low
## Recommendations
## Raw Output References
PROMPT

    if sic_llm_call "$REPORT_MODEL" "$tmp_dir/report_prompt.txt" "$tmp_dir/report.md" 180; then
        echo -e "${GREEN}📄 Report: $tmp_dir/report.md${NC}"
        echo -e "${BLUE}--- REPORT PREVIEW (first 15 lines) ---${NC}"
        head -15 "$tmp_dir/report.md"
        echo -e "${BLUE}----------------------------------------${NC}"
    else echo -e "${YELLOW}⚠  Report generation failed. Raw data: $tmp_dir/vuln/${NC}"
    fi

    sed -i "/${run_id}/s/|running|/|complete|/" "${SIC_INDEX}" 2>/dev/null || true

    echo ""
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ${SIC_MODULE_NAME} — PIPELINE COMPLETE        ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
    echo -e "  Run ID:    ${CYAN}${run_id}${NC}"
    echo -e "  Goal:      ${YELLOW}${goal}${NC}"
    echo -e "  Target:    ${YELLOW}${target}${NC}"
    echo -e "  Saved to:  ${YELLOW}${tmp_dir}${NC}"
    echo -e "  Report:    ${YELLOW}${tmp_dir}/report.md${NC}"
    echo -e "${GREEN}══════════════════════════════════════════${NC}"

    rm -f "$lock_file"
}

sic_history() {
    local n="${1:-20}"
    if [[ ! -f "$SIC_INDEX" ]] || [[ ! -s "$SIC_INDEX" ]]; then
        echo "No runs recorded yet."
        return 0
    fi
    echo -e "${CYAN}══ SIC Run History (last ${n}) ══${NC}"
    printf "%-5s %-12s %-20s %-19s %-8s %s\n" "#" "MODULE" "TARGET" "TIMESTAMP" "STATUS" "GOAL"
    echo "────────────────────────────────────────────────────────────────────────────────"
    local count=0
    tac "$SIC_INDEX" | head -"$n" | while IFS='|' read -r run_id module target ts status goal_str; do
        count=$(( count + 1 ))
        local status_color="$GREEN"
        [[ "$status" == "running" ]] && status_color="$YELLOW"
        printf "%-5s %-12s %-20s %-19s " "$count" "$module" "${target:0:20}" "$ts"
        echo -e "${status_color}${status}${NC} ${goal_str:0:40}"
    done
    echo ""
}

sic_report() {
    local run_ref="${1:-last}"
    local run_dir=""
    if [[ "$run_ref" == "last" ]]; then
        run_dir=$(ls -td "${SIC_RUNS_DIR}"/*/  2>/dev/null | head -1)
    else
        run_dir="${SIC_RUNS_DIR}/${run_ref}"
    fi
    if [[ -z "$run_dir" ]] || [[ ! -d "$run_dir" ]]; then
        echo "[!] Run not found: ${run_ref}"
        return 1
    fi
    local report="${run_dir}/report.md"
    if [[ -f "$report" ]]; then
        echo -e "${CYAN}══ Report: ${run_dir} ══${NC}"
        cat "$report"
    else
        echo "[!] No report.md in ${run_dir}"
        ls "$run_dir"/vuln/ 2>/dev/null || true
    fi
}

# Alias commands
alias sic-history='sic_history'
alias sic-report='sic_report'