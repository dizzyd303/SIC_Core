#!/bin/bash
#===============================================================================
# SIC_COPE.sh — Scarface Intelligence Core | DevOps / Infrastructure Module
#
# Usage:
#   ./SIC_COPE.sh "check all microservice health endpoints"
#   ./SIC_COPE.sh "inspect Kubernetes pods and database health"
#   ./SIC_COPE.sh "analyze application logs for recent errors"
#
# Part of: SIC_Security | SIC_Skip | SIC_Diagnostics | SIC_COPE
#===============================================================================

SIC_CORE="$(cd "$(dirname "$0")" && pwd)/sic_core.sh"
[[ ! -f "$SIC_CORE" ]] && SIC_CORE="/usr/local/lib/sic_core.sh"
source "$SIC_CORE"
sic_check_version 1 3

sic_register_module \
    --name "SIC_COPE" \
    --tools "curl, jq, psql, kubectl, docker, systemctl, journalctl, htop, df, free, uptime, ping, ss, netstat, lsof, top, grep, awk, sed, tail, head, watch, python3, psql, mysql, redis-cli" \
    --danger 'rm -rf /|mkfs|dd of=/dev/sd|nc -e /bin|bash -i >|sh -i >|chmod 777 /|kubectl delete |docker system prune -a -f|DROP TABLE|DROP DATABASE|truncate table' \
    --plan \
        "1. Check all microservice health endpoints and API availability" \
        "2. Query database connection pool status and replication lag" \
        "3. Inspect Kubernetes pod status, deployments, and resource usage" \
        "4. Review application and infrastructure logs for recent errors" \
        "5. Generate infrastructure health and performance report"

# ─────────────────────────────────────────
# sic_run_module_suite() — COPE infrastructure checks
# ─────────────────────────────────────────
sic_run_module_suite() {
    local target="$1" tmp_dir="$2" visa_cfg="$3"
    sic_parse_visa_cfg "$visa_cfg"

    echo ""
    echo -e "${PURPLE}☁  COPE INFRASTRUCTURE CHECK: ${target:-local system}${NC}"
    mkdir -p "$tmp_dir/vuln"

    # [1/5] System health baseline
    echo -e "${CYAN}  [1/5] System resource health...${NC}"
    { echo "=== UPTIME ==="; uptime
      echo "=== MEMORY ==="; free -h
      echo "=== DISK ===";   df -h | grep -E '^/dev/|Filesystem'
      echo "=== TOP PROCESSES (by CPU) ==="; ps aux --sort=-%cpu | head -10
      echo "=== TOP PROCESSES (by MEM) ==="; ps aux --sort=-%mem | head -10
      echo "=== NETWORK CONNECTIONS ==="; ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || echo "ss/netstat not available"
    } > "$tmp_dir/vuln/system_health.txt"
    echo -e "${GREEN}     System health baseline saved${NC}"

    # [2/5] Docker health
    echo -e "${CYAN}  [2/5] Container health (Docker)...${NC}"
    if command -v docker &>/dev/null; then
        { echo "=== DOCKER PS ==="
          docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
          echo "=== DOCKER STATS ==="
          docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | head -20
        } > "$tmp_dir/vuln/docker_health.txt" 2>/dev/null || \
            echo "Docker not running or permission denied" > "$tmp_dir/vuln/docker_health.txt"
        echo -e "${GREEN}     Docker health checked${NC}"
    else
        echo "Docker not installed" > "$tmp_dir/vuln/docker_health.txt"
    fi

    # [3/5] Kubernetes health
    echo -e "${CYAN}  [3/5] Kubernetes cluster health...${NC}"
    if command -v kubectl &>/dev/null; then
        { echo "=== KUBECTL NODES ==="
          kubectl get nodes -o wide 2>/dev/null || echo "kubectl not connected"
          echo "=== KUBECTL PODS (all namespaces) ==="
          kubectl get pods --all-namespaces 2>/dev/null | head -30
          echo "=== KUBECTL SERVICES ==="
          kubectl get svc --all-namespaces 2>/dev/null | head -20
        } > "$tmp_dir/vuln/k8s_health.txt" 2>/dev/null || \
            echo "kubectl not connected" > "$tmp_dir/vuln/k8s_health.txt"
        echo -e "${GREEN}     Kubernetes health checked${NC}"
    else
        echo "kubectl not installed" > "$tmp_dir/vuln/k8s_health.txt"
    fi

    # [4/5] Service endpoint checks
    echo -e "${CYAN}  [4/5] Service endpoint health...${NC}"
    if [[ "$target" =~ ^https?:// ]]; then
        curl -s -o /dev/null -w "  %{http_code} %{time_total}s %{url_effective}\n" \
            "$target" > "$tmp_dir/vuln/endpoint_check.txt" 2>/dev/null || true
    elif [[ "$target" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        for ep in health healthz ready livez api/health; do
            for scheme in https http; do
                curl -s -o /dev/null -w "  ${scheme}://${target}/${ep}: %{http_code} (%{time_total}s)\n" \
                    "${scheme}://${target}/${ep}" >> "$tmp_dir/vuln/endpoint_check.txt" 2>/dev/null || true
            done
        done
    else
        for port in 80 443 3000 5000 8000 8080 8443 9090 5432 6379; do
            timeout 2 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null \
                && echo "  Port $port: OPEN" || echo "  Port $port: closed"
        done > "$tmp_dir/vuln/endpoint_check.txt" 2>/dev/null || true
    fi
    echo -e "${GREEN}     Endpoint checks complete${NC}"

    # [5/5] AI Infrastructure Analysis
    echo -e "${CYAN}  [5/5] AI infrastructure analysis...${NC}"
    { echo "=== SYSTEM HEALTH ==="; cat "$tmp_dir/vuln/system_health.txt" 2>/dev/null
      echo "=== DOCKER ===";       cat "$tmp_dir/vuln/docker_health.txt" 2>/dev/null
      echo "=== KUBERNETES ===";   head -30 "$tmp_dir/vuln/k8s_health.txt" 2>/dev/null
      echo "=== ENDPOINTS ===";    cat "$tmp_dir/vuln/endpoint_check.txt" 2>/dev/null
    } > "$tmp_dir/vuln/infra_collated.txt"

    cat > "$tmp_dir/threat_prompt.txt" <<PROMPT
You are a senior DevOps/SRE engineer reviewing infrastructure health for a ride-share platform.

Provide:
1. Critical issues (down services, resource exhaustion, failing health checks)
2. Infrastructure health summary (CPU, memory, disk, containers, k8s)
3. Performance bottlenecks and scaling concerns
4. Recommended actions prioritized by urgency

Be concise and professional. No reasoning preamble.

Infrastructure Data:
$(cat "$tmp_dir/vuln/infra_collated.txt")
PROMPT

    sic_llm_call "$THREAT_MODEL" "$tmp_dir/threat_prompt.txt" \
        "$tmp_dir/vuln/threat_analysis.txt" 120 || true

    echo -e "${BLUE}--- INFRASTRUCTURE ANALYSIS PREVIEW ---${NC}"
    head -20 "$tmp_dir/vuln/threat_analysis.txt"
    echo -e "${BLUE}----------------------------------------${NC}"
}

sic_run "$@"

