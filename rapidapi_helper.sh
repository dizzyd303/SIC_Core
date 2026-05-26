#!/bin/bash
#===============================================================================
# rapidapi_helper.sh — RapidAPI wrappers for SIC Platform
# Source this from SIC_Skip.sh or other modules to use RapidAPI endpoints.
#
# Required env:   RAPIDAPI_KEY (set in .bashrc or exported before running)
# Optional env:   RAPIDAPI_TIMEOUT (default: 20 seconds per call)
#
# Functions:
#   rapid_social_links   "full name"         — Search social platforms by name
#   rapid_linkedin       "first" "last"      — Search LinkedIn people by name  
#   rapid_email_search   "name" "domain"     — Find email addresses
#   rapid_web_search     "query"             — Google search (clean JSON)
#   rapid_all            "first" "last" "city" "state" — Run all above + merge
#===============================================================================

[[ -n "${RAPIDAPI_HELPER_LOADED:-}" ]] && return 0
RAPIDAPI_HELPER_LOADED=1

RAPIDAPI_TIMEOUT="${RAPIDAPI_TIMEOUT:-20}"

# ─────────────────────────────────────────
# _rapid_curl() — internal: make RapidAPI call with error handling
# ─────────────────────────────────────────
_rapid_curl() {
    local url="$1" host="$2" outfile="$3"
    [[ -z "${RAPIDAPI_KEY:-}" ]] && { echo '{"error":"RAPIDAPI_KEY not set"}' > "$outfile"; return 1; }
    curl -s --max-time "$RAPIDAPI_TIMEOUT" "$url" \
        -H "x-rapidapi-key: $RAPIDAPI_KEY" \
        -H "x-rapidapi-host: $host" \
        2>/dev/null > "$outfile"
    local ec=$?
    if [[ $ec -ne 0 ]]; then
        echo "{\"error\":\"curl_exit_${ec}\"}" > "$outfile"
        return 1
    fi
    # Check for API-level error
    if grep -q '"error"' "$outfile" 2>/dev/null; then
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────
# rapid_social_links() — Search social platforms by name
# Returns: JSON file at $outfile with platform → [urls] structure
# ─────────────────────────────────────────
rapid_social_links() {
    local person_name="$1" outfile="${2:-/tmp/rapid_social_links.json}"
    local query
    query=$(echo "$person_name" | sed 's/ /+/g')
    _rapid_curl \
        "https://social-links-search.p.rapidapi.com/search-social-links?query=${query}" \
        "social-links-search.p.rapidapi.com" \
        "$outfile"
    local ec=$?
    if [[ $ec -eq 0 ]] && [[ -s "$outfile" ]]; then
        echo "[RAPID] Social Links Search: $(jq '.data | length' "$outfile" 2>/dev/null || echo 'results found')"
    else
        echo "[RAPID] Social Links Search: no results or error"
    fi
    return $ec
}

# ─────────────────────────────────────────
# rapid_linkedin() — Search LinkedIn by first/last name
# Returns: JSON file at $outfile
# ─────────────────────────────────────────
rapid_linkedin() {
    local first="$1" last="$2" outfile="${3:-/tmp/rapid_linkedin.json}"
    _rapid_curl \
        "https://fresh-linkedin-scraper-api.p.rapidapi.com/api/v1/search/people?first_name=${first}&last_name=${last}" \
        "fresh-linkedin-scraper-api.p.rapidapi.com" \
        "$outfile"
    local ec=$?
    if [[ $ec -eq 0 ]] && [[ -s "$outfile" ]]; then
        local count; count=$(jq '.data | length' "$outfile" 2>/dev/null || echo "0")
        echo "[RAPID] LinkedIn Search: $count profiles"
    else
        echo "[RAPID] LinkedIn Search: no results or error"
    fi
    return $ec
}

# ─────────────────────────────────────────
# rapid_web_search() — Google search via SerpAPI or similar
# Falls back to a basic curl search if API key limited
# ─────────────────────────────────────────
rapid_web_search() {
    local query="$1" outfile="${2:-/tmp/rapid_web_search.json}"
    local qenc; qenc=$(echo "$query" | sed 's/ /%20/g')
    # Try OpenWebNinja Google Search API if available
    _rapid_curl \
        "https://google-search-results-api.p.rapidapi.com/search?query=${qenc}&num=20" \
        "google-search-results-api.p.rapidapi.com" \
        "$outfile" 2>/dev/null || {
        # Fallback: use Wikipedia API + GitHub as a free alternative
        local sq; sq=$(echo "$query" | tr ' ' '+')
        curl -sL "https://api.github.com/search/users?q=${sq}&per_page=20" > "$outfile" 2>/dev/null || true
        echo "[RAPID] Web Search: GitHub users fallback"
        return 0
    }
    echo "[RAPID] Web Search: results saved"
    return 0
}

# ─────────────────────────────────────────
# rapid_all() — Run all RapidAPI lookups for a person, merge into one report
# ─────────────────────────────────────────
rapid_all() {
    local first="$1" last="$2" city="${3:-}" state="${4:-}" outdir="${5:-/tmp/rapid_results}"
    mkdir -p "$outdir"

    local full_name="${first} ${last}"
    [[ -n "$city" ]] && full_name="${full_name}, ${city}"
    [[ -n "$state" ]] && full_name="${full_name}, ${state}"

    echo -e "${CYAN}  [RAPID] Running RapidAPI lookups for: ${first} ${last}${NC}"

    # Run all in parallel
    rapid_social_links "${first} ${last}" "$outdir/social_links.json" &
    local pid_social=$!
    rapid_linkedin "$first" "$last" "$outdir/linkedin.json" &
    local pid_li=$!
    rapid_web_search "${first} ${last} ${city} ${state}" "$outdir/web_search.json" &
    local pid_web=$!

    wait $pid_social 2>/dev/null; wait $pid_li 2>/dev/null; wait $pid_web 2>/dev/null

    # ── Merge into a unified summary ──
    local merged="$outdir/rapid_summary.json"
    python3 -c "
import json, os, sys

result = {
    'target': {'first': '$first', 'last': '$last', 'city': '$city', 'state': '$state'},
    'facebook': [], 'instagram': [], 'twitter': [], 'linkedin': [], 
    'other_platforms': [], 'github_users': [], 'web_results': []
}

# Social Links
sl_file = '$outdir/social_links.json'
if os.path.exists(sl_file) and os.path.getsize(sl_file) > 0:
    try:
        with open(sl_file) as f:
            data = json.load(f)
        platforms = data.get('data', data)
        if isinstance(platforms, dict):
            for platform, urls in platforms.items():
                if isinstance(urls, list):
                    for url in urls:
                        entry = {'platform': platform, 'url': url}
                        p = platform.lower()
                        if p in ('facebook', 'instagram', 'twitter', 'linkedin'):
                            result[p].append(entry)
                        else:
                            result['other_platforms'].append(entry)
    except: pass

# LinkedIn
li_file = '$outdir/linkedin.json'
if os.path.exists(li_file) and os.path.getsize(li_file) > 0:
    try:
        with open(li_file) as f:
            data = json.load(f)
        profiles = data.get('data', [])
        if isinstance(profiles, list):
            for p in profiles:
                result['linkedin'].append({
                    'platform': 'linkedin',
                    'url': p.get('profile_url', p.get('url', '')),
                    'name': p.get('name', ''),
                    'headline': p.get('headline', ''),
                    'location': p.get('location', '')
                })
    except: pass

# Web / GitHub fallback
web_file = '$outdir/web_search.json'
if os.path.exists(web_file) and os.path.getsize(web_file) > 0:
    try:
        with open(web_file) as f:
            data = json.load(f)
        items = data.get('items', [])
        for item in items:
            result['github_users'].append({
                'login': item.get('login', ''),
                'url': item.get('html_url', '')
            })
    except: pass

# Stats
result['stats'] = {
    'total_profiles': len(result['facebook']) + len(result['instagram']) + len(result['twitter']) + len(result['linkedin']) + len(result['other_platforms']),
    'by_platform': {
        'facebook': len(result['facebook']),
        'instagram': len(result['instagram']),
        'twitter': len(result['twitter']),
        'linkedin': len(result['linkedin']),
        'other': len(result['other_platforms'])
    }
}

with open('$merged', 'w') as f:
    json.dump(result, f, indent=2)
print(f'[RAPID] Summary: {result[\"stats\"][\"total_profiles\"]} total profiles found')
" 2>/dev/null || echo "[RAPID] Merge failed"

    echo -e "${GREEN}  [RAPID] Results saved to: $merged${NC}"
    echo "$merged"
}

