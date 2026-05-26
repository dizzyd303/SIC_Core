# Function to call Unsloth API and extract the response text
call_llm() {
    local system_prompt="$1"
    local user_message="$2"
    
    # Check if Unsloth Studio is running
    if ! curl -s "http://127.0.0.1:8888/api/health" > /dev/null 2>&1; then
        echo "ERROR: Unsloth Studio is not running. Please start it with 'unsloth studio'"
        return 1
    fi
    
    # Make the API call using a more precise endpoint and format
    local response
    response=$(curl -s -X POST "http://127.0.0.1:8888/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --arg system "$system_prompt" \
            --arg user "$user_message" \
            '{model: $model, messages: [{role: "system", content: $system}, {role: "user", content: $user}], stream: false}')")
    
    # Try multiple possible response formats, with a focus on the OpenAI-compatible one
    local answer
    answer=$(echo "$response" | jq -r '
        .choices[0].message.content // 
        .message.content // 
        .response // 
        .content // 
        "⚠️ No valid response from API. Check that a model is loaded in Unsloth Studio."')
    
    echo "$answer"
}