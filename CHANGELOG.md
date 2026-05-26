# SIC Platform — Change Log
# SIC Platform Created by SpYdA573 (Daniel Young)
## Files Modified

### `sic_core.sh` — Shared Pipeline Core
**1. CIDR Validation (`sic_validate_cidr()`)**
- New function rejects `/8` or larger (16M+ IPs) — aborts immediately with clear error
- Warns on `/9` through `/16` ranges (large but allowed)
- Called during `sic_run()` after target extraction, before architect stage

**2. Target Extraction Fix (`sic_extract_target()`)**
- Fixed regex ordering: IP/CIDR checked first, then bare hostname, then domain
- Fixed regex to correctly strip `recon`, `scan`, `analyze`, `audit`, `check`, `enumerate`, `test` prefixes
- Added stripping of trailing suffixes (`for open ports`, `for vulnerabilities`, etc.)
- Strips common stopwords (`and`, `for`, `the`, `with`, `on`, `to`, `of`, `in`, `at`)

**3. Goal Type Detection Fix**
- Fixed regex for hostname-only targets (no dots) — classifies as "domain" not "ip"
- Ensures bare words like `localhost` or `SPY` are treated as valid targets

**4. Fallback Script Safety**
- AI-generated fallback scripts use `(cd "$tmp_dir/vuln")` to avoid filesystem pollution

**5. `--skip-coder` Flag Support**
- New optional flag for `sic_register_module()`: `--skip-coder`
- When set, coder stage creates no-op placeholders instead of calling the AI model
- Prevents deterministic modules (Stocks, Cloud) from generating bad security scripts

**6. Module Header Updated**
- Module list updated: `SIC_Security, SIC_Skip, SIC_Diagnostics, SIC_COPE, SIC_Cloud_Security, SIC_Stocks`

### `SIC_Security.sh` — Network Security Module

**1. CIDR-Aware Scanning**
- Detects CIDR ranges vs single hosts
- For CIDR: host discovery first (`-sn`), then scans live hosts only (top 100 ports)
- For CIDR: skips web tools (whatweb, ffuf, nuclei, testssl)
- For single hosts: unchanged (top 1000 ports with `-sV -sC`)

**2. Sudo Hang Fix**
- Added `timeout 2` to `sudo -n true` check — prevents infinite hang in non-interactive sessions

## Files Created

### `SIC_Stocks.sh` — Stock Trading Pipeline (renamed from SIC_Stonks.sh)

```
./SIC_Stocks.sh "analyze AAPL"
AUTO_RUN=1 PAPER_TRADE=1 ./SIC_Stocks.sh "scan BTC-USD"
```

| Phase | Description |
|-------|-------------|
| 1/4 | Fetch market data + technical indicators via yfinance |
| 2/4 | Generate BUY/SELL/HOLD signal with 0-100 confidence score |
| 3/4 | Paper trade (optional, PAPER_TRADE=1) |
| 4/4 | AI market summary (if model available) |

**Indicators:** RSI(14), MACD, SMA(20/50/200), Bollinger Bands, annualized volatility, 52-week position, volume spikes

**Signal Logic:** 0-30 SELL, 31-69 HOLD, 70-100 BUY — weighted from all indicators

**Dependencies:** `pip install yfinance pandas numpy --break-system-packages`

### `SIC_Cloud_Security.sh` — Cloud Audit Skeleton

Provider functions for AWS/GCP/Azure with auto-detection. Registered with `--skip-coder`.

### `SIC_BRIDGE.sh` — Function-Calling Bridge for Local AI Models

Gives ollama/LM Studio/vLLM/NVIDIA NIM models CLI+filesystem access. 7 registered tools, OpenAI-compatible API, full tool-call loop.

## File Renames

| Old | New |
|-----|-----|
| SIC_Stonks.sh | SIC_Stocks.sh |

Symlinks: `~/SIC_Stonks.sh` removed, `~/SIC_Stocks.sh` added.

## Deployment Status

| File | `/usr/local/bin/` | `sic-platform/` | `~/` symlink |
|------|-------------------|-----------------|--------------|
| SIC_Security.sh | ✅ deployed (pre-timeout-fix) | ✅ updated | ✅ |
| sic_core.sh | ✅ deployed | ✅ updated | N/A |
| SIC_Stocks.sh | ❌ not deployed | ✅ created | ✅ |
| SIC_Cloud_Security.sh | ❌ not deployed | ✅ created | ✅ |
| SIC_BRIDGE.sh | ❌ not deployed | ✅ created | ✅ |

To deploy system-wide (interactive sudo needed):
```bash
for f in sic_core.sh SIC_Security.sh SIC_Stocks.sh SIC_Cloud_Security.sh SIC_BRIDGE.sh; do
  sudo cp "/home/spyda573/sic-platform/$f" "/usr/local/bin/$f"
done
```
