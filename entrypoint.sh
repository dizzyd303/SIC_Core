#!/bin/bash
#===============================================================================
# entrypoint.sh — SIC Platform Docker Entrypoint
# Starts Ollama server, then executes the requested SIC module.
#
# Usage:
#   docker run ... sic-platform SIC_Security.sh "recon example.com"
#   docker run ... sic-platform SIC_Skip.sh "find accounts for johndoe"
#===============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  SIC Platform — Scarface Intelligence   ║${NC}"
echo -e "${GREEN}║  Core ready in container                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"

# Start Ollama server in background
echo -e "${YELLOW}[*] Starting Ollama server...${NC}"
ollama serve &
OLLAMA_PID=$!
sleep 2

# Wait for Ollama to be ready
echo -e "${YELLOW}[*] Waiting for Ollama API...${NC}"
for i in $(seq 1 30); do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo -e "${GREEN}[✓] Ollama API ready${NC}"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo -e "${RED}[!] Ollama failed to start within 30s${NC}"
        kill $OLLAMA_PID 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

export OLLAMA_HOST="http://localhost:11434"
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_MAX_LOADED_MODELS=2

# If no args, drop to interactive shell
if [[ $# -eq 0 ]]; then
    echo ""
    echo -e "${YELLOW}Available modules:${NC}"
    echo "  SIC_Security.sh    — Security assessment / bug bounty recon"
    echo "  SIC_Skip.sh        — Skip tracing / OSINT investigation"
    echo "  SIC_Diagnostics.sh — Vehicle / system diagnostics"
    echo "  SIC_COPE.sh        — DevOps infrastructure checks"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  docker run ... sic-platform SIC_Security.sh \"recon example.com\""
    echo ""
    exec /bin/bash
fi

# Execute the requested module
MODULE="$1"
shift

if [[ -f "/usr/local/bin/${MODULE}" ]]; then
    echo -e "${GREEN}[*] Running: ${MODULE} $*${NC}"
    exec "/usr/local/bin/${MODULE}" "$@"
elif [[ -f "$(pwd)/${MODULE}" ]]; then
    echo -e "${GREEN}[*] Running: ${MODULE} $*${NC}"
    exec "$(pwd)/${MODULE}" "$@"
else
    echo -e "${RED}[!] Module not found: ${MODULE}${NC}"
    echo "Available: SIC_Security.sh, SIC_Skip.sh, SIC_Diagnostics.sh, SIC_COPE.sh"
    exit 1
fi

