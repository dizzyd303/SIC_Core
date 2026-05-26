#!/bin/bash
# sic_apis.sh – Central API Gateway for SIC & Heartland
# Loads keys and provides functions for all external APIs

# Load keys (if not already loaded)
if [[ -z "$APILAYER_KEY" ]]; then
    source ~/.config/sic/api_keys.env 2>/dev/null || {
        echo "ERROR: API keys not found at ~/.config/sic/api_keys.env"
        return 1
    }
fi

# -------------------------------------------------------------------
# Helper: make API request and handle errors
# -------------------------------------------------------------------
_api_request() {
    local url="$1"
    local auth_header="$2"
    local method="${3:-GET}"
    local data="$4"
    
    local curl_cmd="curl -s -X $method"
    [[ -n "$auth_header" ]] && curl_cmd+=" -H '$auth_header'"
    [[ -n "$data" ]] && curl_cmd+=" -H 'Content-Type: application/json' -d '$data'"
    curl_cmd+=" '$url'"
    
    local response
    response=$(eval $curl_cmd)
    
    # Check for error (naive)
    if echo "$response" | grep -qi '"error"'; then
        echo "API Error: $response" >&2
        return 1
    fi
    echo "$response"
    return 0
}

# -------------------------------------------------------------------
# Google Search (APILayer)
# usage: google_search "query" [num_results]
# -------------------------------------------------------------------
google_search() {
    local query="$1"
    local num="${2:-10}"
    local url="https://api.apilayer.com/google/search?q=$(echo "$query" | sed 's/ /%20/g')&num=$num"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# Bing Search
# -------------------------------------------------------------------
bing_search() {
    local query="$1"
    local url="https://api.apilayer.com/bing/search?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# Brave Search
# -------------------------------------------------------------------
brave_search() {
    local query="$1"
    local url="https://api.apilayer.com/brave/search?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# Google Images
# -------------------------------------------------------------------
google_images() {
    local query="$1"
    local url="https://api.apilayer.com/google/images?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# Google Maps
# -------------------------------------------------------------------
google_maps() {
    local query="$1"
    local url="https://api.apilayer.com/google/maps?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# Google News
# -------------------------------------------------------------------
google_news() {
    local query="$1"
    local url="https://api.apilayer.com/google/news?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# Google Shopping
# -------------------------------------------------------------------
google_shopping() {
    local query="$1"
    local url="https://api.apilayer.com/google/shopping?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# Google Videos
# -------------------------------------------------------------------
google_videos() {
    local query="$1"
    local url="https://api.apilayer.com/google/videos?q=$(echo "$query" | sed 's/ /%20/g')"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# IP to Geolocation (APILayer)
# -------------------------------------------------------------------
ip_to_geo() {
    local ip="$1"
    local url="https://api.apilayer.com/ip_to_location/$ip"
    _api_request "$url" "apikey: $APILAYER_KEY"
}

# -------------------------------------------------------------------
# Email Verification
# -------------------------------------------------------------------
email_verify() {
    local email="$1"
    local url="https://api.apilayer.com/email_verification/check?email=$email"
    _api_request "$url" "apikey: $EMAIL_VERIFY_KEY"
}

# -------------------------------------------------------------------
# Phone Number Verification
# -------------------------------------------------------------------
phone_verify() {
    local number="$1"
    local url="https://api.apilayer.com/number_verification/validate?number=$number"
    _api_request "$url" "apikey: $NUMBER_VERIFY_KEY"
}

# -------------------------------------------------------------------
# IBAN / SWIFT Validation (assume APILayer endpoint)
# -------------------------------------------------------------------
iban_validate() {
    local iban="$1"
    local url="https://api.apilayer.com/iban/validate?iban=$iban"
    _api_request "$url" "apikey: $IBAN_KEY"
}

# -------------------------------------------------------------------
# PDF Generation (PDF Layer – different endpoint)
# -------------------------------------------------------------------
pdf_generate() {
    local html_content="$1"
    local output_file="$2"
    # This is a simplified version – PDF Layer expects HTML and returns PDF binary
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

# -------------------------------------------------------------------
# Scraper API (scrape any website)
# -------------------------------------------------------------------
scrape_url() {
    local url="$1"
    local api_url="http://api.scraperapi.com?api_key=$SCRAPERAPI_KEY&url=$(echo "$url" | sed 's/ /%20/g')"
    curl -s "$api_url"
}

# -------------------------------------------------------------------
# Domain Name Discovery (APILayer – might be whois related)
# -------------------------------------------------------------------
domain_discovery() {
    local domain="$1"
    local url="https://api.apilayer.com/domain_discovery/search?domain=$domain"
    _api_request "$url" "apikey: $DOMAIN_DISCOVERY_KEY"
}

# -------------------------------------------------------------------
# User Agent API (get a random user agent)
# -------------------------------------------------------------------
random_user_agent() {
    curl -s "https://api.apilayer.com/user_agent" -H "apikey: $USERAGENT_KEY"
}

# -------------------------------------------------------------------
# Exchange Rates
# -------------------------------------------------------------------
exchange_rates() {
    local base="${1:-USD}"
    curl -s "https://api.apilayer.com/exchangerates_data/latest?base=$base" \
        -H "apikey: $EXCHANGE_RATES_KEY"
}

# -------------------------------------------------------------------
# Market Stack (stock data)
# -------------------------------------------------------------------
market_stack() {
    local symbol="$1"
    curl -s "http://api.marketstack.com/v1/eod?access_key=$MARKETSTACK_KEY&symbols=$symbol"
}

# -------------------------------------------------------------------
# IPAPI (detailed IP geolocation)
# -------------------------------------------------------------------
ipapi_lookup() {
    local ip="$1"
    curl -s "https://ipapi.co/$ip/json/"
}

# -------------------------------------------------------------------
# Aviation Stack (flight info)
# -------------------------------------------------------------------
aviation_flight() {
    local flight_number="$1"
    curl -s "http://api.aviationstack.com/v1/flights?access_key=$AVIATIONSTACK_KEY&flight_number=$flight_number"
}

echo "SIC API Library loaded. Available functions:"
declare -F | grep -v "_api_request" | awk '{print $3}'
