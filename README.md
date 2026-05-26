# SIC Platform — Scarface Intelligence Core
# Created by SpYdA573 (Daniel Young)

## What's in the box

| Module | Purpose |
|--------|---------|
| `SIC_Security.sh` | Bug bounty recon, port scanning, vuln detection |
| `SIC_Skip.sh` | Skip tracing, OSINT, socialmedia discovery |
| `SIC_Diagnostics.sh` | Vehicle/system diagnostics |
| `SIC_COPE.sh` | DevOps infrastructure health checks |

All modules share the **same AI pipeline** (Architect → Coder → Reviewer → Execute → Report).
Each module just declares its tools, dangerous patterns, default plan, and recon suite.

---

## Local Install (no Docker)

```bash
# System-wide (requires sudo)
sudo chmod +x *.sh
sudo ./install.sh

# Or user-local
./install.sh --user
source ~/.bashrc
```

---

## SIC_Security — Bug Bounty Recon

```bash
# Basic scan
SIC_Security.sh "recon example.com for open ports and vulns"

# Visa-compliant (1 req/sec, X-Hackerone header)
VISA_MODE=1 H1_USERNAME=spyda573 SIC_Security.sh "scan visa.com"

# Non-interactive
AUTO_RUN=1 SIC_Security.sh "scan 192.168.1.1"

# Exploit/pentest mode (triggers Enhancer stage)
SIC_Security.sh "pentest pentestlab.com for SQL injection and XSS"
```

What it does:
1. AI Architect generates a phase plan
2. AI Coder writes a bash script per phase
3. Safety reviewer checks for dangerous commands
4. Executes the scripts
5. Runs professional recon suite: nmap → whatweb → testssl → ffuf → nuclei → AI threat analysis
6. Generates markdown report

---

## SIC_Skip — OSINT / Skip Tracing

```bash
# Find social media accounts for a username
SIC_Skip.sh "find all social media accounts for johndoe"

# Domain OSINT
SIC_Skip.sh "gather OSINT on example.com"

# Email discovery
AUTO_RUN=1 SIC_Skip.sh "find email addresses associated with acme.com"
```

What it does:
1. AI phases → bash scripts
2. DNS enumeration (dig, subfinder, assetfinder)
3. WHOIS lookup
4. Social media search (sherlock, theHarvester)
5. AI intelligence analysis report

---

## SIC_Diagnostics — Vehicle / System Diagnostics

```bash
# Read vehicle diagnostic codes
SIC_Diagnostics.sh "read diagnostic trouble codes from vehicle"

# Check sensor data
SIC_Diagnostics.sh "check engine sensor data"

# Analyze system failures
SIC_Diagnostics.sh "analyze recent system failures from logs"
```

What it does:
1. AI phases → bash scripts
2. System health baseline (CPU, memory, disk)
3. Sensor data collection (lm-sensors)
4. Log analysis (journalctl, dmesg)
5. AI diagnostic summary report

---

## SIC_COPE — DevOps / Infrastructure

```bash
# Check microservice health
SIC_COPE.sh "check all microservice health endpoints"

# Kubernetes + Docker health
SIC_COPE.sh "inspect Kubernetes pods and database health"

# Log analysis
SIC_COPE.sh "analyze application logs for recent errors"
```

What it does:
1. AI phases → bash scripts
2. System resource health
3. Docker container health
4. Kubernetes cluster health
5. Service endpoint checks
6. AI infrastructure analysis report

---

## Docker Deployment

```bash
# Build the image (pre-pulls all models during build)
docker compose build

# Run security scan
docker compose run --rm sic SIC_Security.sh "recon example.com"

# Visa-compliant scan
docker compose run --rm -e VISA_MODE=1 -e H1_USERNAME=spyda573 \
    sic SIC_Security.sh "scan visa.com"

# Non-interactive
docker compose run --rm -e AUTO_RUN=1 sic \
    SIC_Security.sh "scan example.com"

# Other modules
docker compose run --rm sic SIC_Skip.sh "find social accounts for johndoe"
docker compose run --rm sic SIC_COPE.sh "check microservice health"
docker compose run --rm sic SIC_Diagnostics.sh "analyze system health"

# Interactive shell with all tools available
docker compose run --rm sic
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VISA_MODE` | `0` | Set to `1` for Visa bug bounty compliance |
| `H1_USERNAME` | (empty) | Your HackerOne username (required with VISA_MODE) |
| `AUTO_RUN` | `0` | Set to `1` to skip confirmation prompts |
| `OLLAMA_NUM_PARALLEL` | `1` | Ollama parallel requests (keep at 1 for laptops) |
| `OLLAMA_MAX_LOADED_MODELS` | `2` | Max models loaded simultaneously |

---

## Model Overrides

Each module can override models at the top of its script:

```bash
# In SIC_Security.sh, uncomment and edit:
# ARCHITECT_MODEL="ssfdre38/gemma4-nano:e4b"
# CODER_MODEL="qwen2.5-coder:7b"
# ENHANCER_MODEL="sec-coder:latest"
# THREAT_MODEL="milanjeremic2/deepseek-r1-32b-uncensored:latest"
# REPORT_MODEL="smollm:1.7b"
```

Or via environment variables:

```bash
CODER_MODEL=qwen2.5-coder:7b SIC_Security.sh "recon example.com"
```

---

## File Layout

```
sic-platform/
├── sic_core.sh           # Shared pipeline core (sourced by all modules)
├── SIC_Security.sh        # Security assessment module
├── SIC_Skip.sh            # Skip tracing / OSINT module
├── SIC_Diagnostics.sh     # Vehicle diagnostics module
├── SIC_COPE.sh            # DevOps infrastructure module
├── Dockerfile             # Multi-stage Docker build
├── docker-compose.yml     # Docker Compose config
├── entrypoint.sh          # Docker entrypoint
├── install.sh             # Local install script
├── .env.example           # Environment variable template
└── README.md              # This file
```

## Architecture

```
User Goal
    │
    ▼
┌─────────────────┐
│  1. ARCHITECT   │  LLM breaks goal into 3-5 numbered phases
│  (Huihui 3B)    │
└────────┬────────┘
         ▼
┌─────────────────┐
│  2. CODER       │  LLM writes one bash script per phase
│  (stable-code)  │  Serial execution (prevents RAM thrashing)
└────────┬────────┘
         ▼ (optional)
┌─────────────────┐
│  2B. ENHANCER   │  Adds exploit modules if pentest keywords detected
│  (sec-coder)    │
└────────┬────────┘
         ▼
┌─────────────────┐
│  3. REVIEWER    │  Deterministic safety check (no AI)
│  (grep-based)   │  Blocks recursive calls & dangerous commands
└────────┬────────┘
         ▼
┌─────────────────┐
│  4. EXECUTE     │  Runs phase scripts with 5-min timeout each
└────────┬────────┘
         ▼
┌──────────────────────────┐
│  4B. MODULE SUITE        │  Module-specific tooling
│  (nmap/whatweb/nuclei)   │  SIC_Security runs full recon suite
└────────┬─────────────────┘
         ▼
┌─────────────────┐
│  5. REPORT      │  LLM generates markdown report
│  (smollm 1.7B)  │
└─────────────────┘
```

# Thinking_Bleed
