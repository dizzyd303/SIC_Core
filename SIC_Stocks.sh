#!/bin/bash
#===============================================================================
# SIC_Stocks.sh — Scarface Intelligence Core | Algorithmic Trading Module
#
# Usage:
#   ./SIC_Stocks.sh "analyze AAPL for breakout patterns"
#   ./SIC_Stocks.sh "evaluate MSFT"
#   AUTO_RUN=1 PAPER_TRADE=1 ./SIC_Stocks.sh "scan crypto BTC-USD"
#
# Depends: python3, yfinance, pandas (pip install yfinance pandas numpy)
#
# Part of the SIC platform.
#===============================================================================

SIC_CORE="$(cd "$(dirname "$0")" && pwd)/sic_core.sh"
[[ ! -f "$SIC_CORE" ]] && SIC_CORE="/usr/local/lib/sic_core.sh"
source "$SIC_CORE"
sic_check_version 1 3

# ── Register module ──
sic_register_module \
    --name "SIC_Stocks" \
    --tools "python3, curl, yfinance, pandas, numpy" \
    --danger 'rm -rf /|mkfs|dd of=/dev/sd|>/dev/sda' \
    --plan \
        "1. Fetch current market data and technical indicators" \
        "2. Generate buy/sell/hold signals with confidence scoring" \
        "3. Execute paper trade or print analysis report"

# ─────────────────────────────────────────
# sic_run_module_suite() — Market analysis engine
# ─────────────────────────────────────────
sic_run_module_suite() {
    local target="$1" tmp_dir="$2" visa_cfg="$3"
    sic_parse_visa_cfg "$visa_cfg"
    local paper_trade="${PAPER_TRADE:-0}"
    local interval="${INTERVAL:-1d}"
    local period="${PERIOD:-3mo}"

    echo ""
    echo -e "${PURPLE}📈 STONKS ENGINE: $target${NC}"
    mkdir -p "$tmp_dir/vuln"

    # ── Validate ticker ──
    if ! echo "$target" | grep -qiE '^[A-Z]{1,5}$|^(BTC|ETH|SOL|XRP)[-]?USD$|^[A-Z]{2,5}[-]?USD$'; then
        echo -e "${YELLOW}  [!] '$target' doesn't look like a ticker. Try e.g. 'analyze AAPL'${NC}"
        return
    fi

    # ── [1/4] Fetch market data ──
    echo -e "${CYAN}  [1/4] Fetching market data for $target (${period}, ${interval})...${NC}"
    local data_file="$tmp_dir/vuln/market_data.json"
    local signals_file="$tmp_dir/vuln/signals.txt"

    python3 <<PYEOF 2>&1 | tee "$data_file"
import json, sys
try:
    import yfinance as yf
    ticker = yf.Ticker("$target")
    hist = ticker.history(period="$period", interval="$interval")
    if hist.empty:
        print(json.dumps({"error": "No data returned for $target"}))
        sys.exit(1)
    info = ticker.info or {}
    c = hist["Close"]
    result = {
        "ticker": "$target",
        "current_price": info.get("currentPrice") or info.get("regularMarketPrice") or float(c.iloc[-1]),
        "previous_close": info.get("previousClose"),
        "52w_high": info.get("fiftyTwoWeekHigh"),
        "52w_low": info.get("fiftyTwoWeekLow"),
        "market_cap": info.get("marketCap"),
        "volume": int(hist["Volume"].iloc[-1]),
        "avg_volume": int(hist["Volume"].tail(20).mean()),
        "pe_ratio": info.get("trailingPE"),
        "beta": info.get("beta"),
        "sma_20": float(c.tail(20).mean()),
        "sma_50": float(c.tail(50).mean()) if len(c) >= 50 else None,
        "sma_200": float(c.tail(200).mean()) if len(c) >= 200 else None,
        "last_close": float(c.iloc[-1]),
        "last_open": float(hist["Open"].iloc[-1]),
        "records": len(hist)
    }
    # RSI 14
    if len(c) >= 15:
        delta = c.diff()
        gain = delta.where(delta > 0, 0).rolling(14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
        rs = gain / loss
        result["rsi_14"] = float(100 - (100 / (1 + rs.iloc[-1])))
    # MACD
    if len(c) >= 26:
        e12 = c.ewm(span=12).mean()
        e26 = c.ewm(span=26).mean()
        macd = e12 - e26
        sig = macd.ewm(span=9).mean()
        result["macd"] = float(macd.iloc[-1])
        result["macd_signal"] = float(sig.iloc[-1])
        result["macd_histogram"] = float(macd.iloc[-1] - sig.iloc[-1])
    # Bollinger Bands
    if len(c) >= 20:
        sma = float(c.tail(20).mean())
        std = float(c.tail(20).std())
        result["bb_upper"] = sma + (std * 2)
        result["bb_lower"] = sma - (std * 2)
    # Volatility
    if len(c) >= 30:
        result["volatility"] = float(c.pct_change().tail(30).std() * (252 ** 0.5))
    print(json.dumps(result, indent=2, default=str))
except ImportError as e:
    print(json.dumps({"error": f"Missing dep: {e}. Run: pip install yfinance pandas numpy"}))
    sys.exit(1)
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
PYEOF

    if python3 -c "import json; d=json.load(open('$data_file')); assert 'error' not in d" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Data fetched${NC}"
    else
        echo -e "${RED}  ✗ Fetch failed. See $data_file${NC}"
        grep -o '"error":"[^"]*"' "$data_file" 2>/dev/null || true
        return
    fi

    # ── [2/4] Generate signals ──
    echo -e "${CYAN}  [2/4] Generating signals...${NC}"
    python3 <<PYEOF 2>&1 | tee "$signals_file"
import json
with open('$data_file') as f:
    d = json.load(f)

signals = []
score = 50

rsi = d.get("rsi_14")
if rsi:
    if rsi < 30:
        signals.append(f"OVERSOLD (RSI={rsi:.1f}) — bullish reversal potential")
        score += 15
    elif rsi > 70:
        signals.append(f"OVERBOUGHT (RSI={rsi:.1f}) — bearish reversal risk")
        score -= 15
    elif rsi < 45:
        signals.append(f"WEAK (RSI={rsi:.1f}) — bearish leaning")
        score -= 5
    elif rsi > 55:
        signals.append(f"STRONG (RSI={rsi:.1f}) — bullish leaning")
        score += 5

macd = d.get("macd")
m_sig = d.get("macd_signal")
if macd is not None and m_sig is not None:
    if macd > m_sig:
        signals.append("MACD bullish (above signal)")
        score += 10
    else:
        signals.append("MACD bearish (below signal)")
        score -= 10

s20, s50, close = d.get("sma_20"), d.get("sma_50"), d.get("last_close")
if s20 and s50 and close:
    if close > s20 > s50:
        signals.append("Uptrend (price > SMA20 > SMA50)")
        score += 10
    elif close < s20 < s50:
        signals.append("Downtrend (price < SMA20 < SMA50)")
        score -= 10

bb_u, bb_l = d.get("bb_upper"), d.get("bb_lower")
if bb_u and bb_l and close:
    if close >= bb_u:
        signals.append("At upper Bollinger — overextended")
        score -= 5
    elif close <= bb_l:
        signals.append("At lower Bollinger — bounce potential")
        score += 10

vol, avg_v = d.get("volume"), d.get("avg_volume")
if vol and avg_v and avg_v > 0:
    vr = vol / avg_v
    if vr > 1.5:
        signals.append(f"Volume spike ({vr:.1f}x avg)")

h52, l52 = d.get("52w_high"), d.get("52w_low")
if h52 and l52 and close:
    pct = (close - l52) / (h52 - l52) * 100
    if pct < 20:
        signals.append(f"Near 52w low ({pct:.0f}% of range)")
        score += 5
    elif pct > 80:
        signals.append(f"Near 52w high ({pct:.0f}% of range)")
        score -= 5

score = max(0, min(100, score))
decision = "BUY" if score >= 70 else ("SELL" if score <= 30 else "HOLD")

print(f"TICKER: {d.get('ticker')}")
cp = d.get('current_price')
print(f"PRICE: \${cp:.2f}" if cp else "PRICE: N/A")
print(f"RSI(14): {d.get('rsi_14', 'N/A'):.1f}" if d.get('rsi_14') else "RSI: N/A")
print(f"MACD: {d.get('macd', 'N/A'):.4f}" if d.get('macd') else "MACD: N/A")
print(f"VOL(30d): {d.get('volatility', 'N/A'):.2%}" if d.get('volatility') else "VOL: N/A")
print(f"")
print(f"SCORE: {score}/100")
print(f"RECOMMENDATION: {decision}")
print(f"")
print("SIGNALS:")
for s in signals:
    print(f"  \u2022 {s}")
PYEOF

    echo -e "${GREEN}  ✓ Signals generated${NC}"

    # ── [3/4] Paper trade or report ──
    if [[ "$paper_trade" == "1" ]]; then
        echo -e "${CYAN}  [3/4] Executing paper trade...${NC}"
        local decision; decision=$(grep "RECOMMENDATION:" "$signals_file" | awk '{print $2}')
        local price; price=$(grep "PRICE:" "$signals_file" | grep -oP '\d+\.\d+' | head -1)
        echo -e "${GREEN}  📝 PAPER: ${decision} ${target} @ \$${price}${NC}"
        echo "$(date '+%Y-%m-%d %H:%M') | ${decision} | ${target} | ${price}" >> "$tmp_dir/vuln/paper_trades.log"
    else
        echo -e "${YELLOW}  [3/4] Paper trade off (PAPER_TRADE=1 to enable)${NC}"
    fi

    # ── [4/4] AI market summary ──
    echo -e "${CYAN}  [4/4] AI market summary...${NC}"
    cat > "$tmp_dir/market_prompt.txt" <<PROMPT
You are a financial analyst. Summarize the key signals for ${target}.
Use the data below. Give a clear BUY/HOLD/SELL recommendation with reasoning.
Keep it concise — one paragraph. No preamble.

Data:
$(cat "$data_file" 2>/dev/null | head -30)

Signals:
$(cat "$signals_file" 2>/dev/null)
PROMPT

    if sic_llm_call "$THREAT_MODEL" "$tmp_dir/market_prompt.txt" "$tmp_dir/vuln/market_analysis.txt" 120; then
        echo -e "${GREEN}  ✅ Analysis complete${NC}"
    else
        echo -e "${YELLOW}  ⚠  AI analysis skipped (model unavailable)${NC}"
        echo "AI analysis unavailable" > "$tmp_dir/vuln/market_analysis.txt"
    fi

    echo ""
    echo -e "${BLUE}══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  SIGNAL SUMMARY${NC}"
    echo -e "${BLUE}══════════════════════════════════════════${NC}"
    grep -E "TICKER|PRICE|RECOMMENDATION|SCORE|RSI|MACD|VOL" "$signals_file" 2>/dev/null
    echo ""
    grep "SIGNALS:" -A 99 "$signals_file" 2>/dev/null | tail -n +2
    echo ""
    echo -e "  Signals: ${YELLOW}${signals_file}${NC}"
    [[ -s "$tmp_dir/vuln/market_analysis.txt" ]] && echo -e "  AI Summary:" && head -5 "$tmp_dir/vuln/market_analysis.txt"
    echo -e "${BLUE}══════════════════════════════════════════${NC}"
}

sic_run "$@"

