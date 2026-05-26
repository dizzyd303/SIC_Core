#!/bin/bash
#===============================================================================
# SIC_BRIDGE.sh — Text‑based function calling for local models
# Works with Ollama, Unsloth, LM Studio, vLLM, etc.
# Created by SpYdA573 (Daniel Young)
# TOOL DEFINITIONS (same as before, but now used for prompting only)
# ----------------------------------------------------------------------
TOOL_DESCRIPTIONS=$(cat <<'EOF'
- run_terminal_cmd: {"command": "shell command", "timeout": 60}
- read_file: {"path": "/absolute/path/to/file"}
- write_file: {"path": "/absolute/path/to/file", "content": "text to write"}
- list_files: {"path": "/directory/path"}
- web_search: {"query": "search terms"}
- ollama_list_models: {}
- exit_bridge: {"summary": "final summary of work"}
EOF
)

# ----------------------------------------------------------------------
# EXECUTOR (unchanged)
# ----------------------------------------------------------------------
execute_tool() {
    local name="$1" args="$2"
    case "$name" in
        run_terminal_cmd)
            local cmd; cmd=$(echo "$args" | jq -r '.command // empty')
            local timeout; timeout=$(echo "$args" | jq -r '.timeout // 60')
            [[ -z "$cmd" ]] && echo '{"error":"No command"}' && return 1
            timeout "$timeout" bash -c "$cmd" 2>&1 || echo "Exit code: $?"
            ;;
        read_file)
            local path; path=$(echo "$args" | jq -r '.path // empty')
            [[ -z "$path" ]] && echo '{"error":"No path"}' && return 1
            if [[ -f "$path" ]]; then cat "$path"; else echo "{\"error\":\"File not found: $path\"}"; fi
            ;;
        write_file)
            local path; path=$(echo "$args" | jq -r '.path // empty')
            local content; content=$(echo "$args" | jq -r '.content // empty')
            [[ -z "$path" ]] && echo '{"error":"No path"}' && return 1
            mkdir -p "$(dirname "$path")"
            echo "$content" > "$path"
            echo "{\"status\":\"written\",\"path\":\"$path\"}"
            ;;
        list_files)
            local path; path=$(echo "$args" | jq -r '.path // "."')
            ls -la "$path" 2>&1 || echo "{\"error\":\"Cannot list $path\"}"
            ;;
        web_search)
            local query; query=$(echo "$args" | jq -r '.query // empty')
            [[ -z "$query" ]] && echo '{"error":"No query"}' && return 1
            curl -s "https://lite.duckduckgo.com/lite/?q=${query// /+}" 2>/dev/null | sed -n 's/.*<a[^>]*href="\([^"]*\)"[^>]*>\([^<]*\)<.*/\1 - \2/p' | head -10
            ;;
        ollama_list_models)
            ollama list 2>&1 || echo '{"error":"ollama not available"}'
            ;;
        exit_bridge)
            echo "[[DONE]]"
            ;;
        *)
            echo "{\"error\":\"Unknown tool: $name\"}"
            return 1
            ;;
    esac
}

# ----------------------------------------------------------------------
# MAIN LOOP — parse tool calls from model's text response
# ----------------------------------------------------------------------
main() {
    local user_input="$*"
    [[ -z "$user_input" ]] && echo "Usage: $0 \"your request\"" && exit 1

    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   SIC BRIDGE — Text‑based Tool Calling  ║${NC}"
    echo -e "${BLUE}║   Model: ${MODEL}${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"

    local conversation_history=""
    local iteration=0

    while [[ $iteration -lt $MAX_ITERATIONS ]]; do
        iteration=$((iteration + 1))
        echo -e "\n${YELLOW}─── Iteration ${iteration}/${MAX_ITERATIONS} ───${NC}"

        # Build the system prompt with strict formatting instructions
        local system_prompt="You are an AI with filesystem and terminal access. To perform actions, output a single JSON object in the line starting with 'TOOL_CALL:'.

Available tools:
${TOOL_DESCRIPTIONS}

RULES:
1. You will NEVER ask me to run commands. Instead, output exactly:
   TOOL_CALL: {\"tool\": \"tool_name\", \"arguments\": {...}}
2. After I execute the tool, I will show you the result.
3. Then you can output another TOOL_CALL, or if you are done, output:
   TOOL_CALL: {\"tool\": \"exit_bridge\", \"arguments\": {\"summary\": \"What was accomplished\"}}
4. You may also output normal text, but only the line starting with 'TOOL_CALL:' will be executed.
5. Escape any double quotes inside strings with backslashes.

User request: ${user_input}"

        # Call the model
        local response
        response=$(curl -s "$API_URL/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $UNSLOTH_API_KEY" \
            -d "$(jq -n \
                --arg model "$MODEL" \
                --arg sys "$system_prompt" \
                --arg hist "$conversation_history" \
                '{model: $model, messages: [{role: "system", content: $sys}, {role: "user", content: $hist + "\nUser request: " + $user_input}], max_tokens: 4096, temperature: 0.2}')")

        local content
        content=$(echo "$response" | jq -r '.choices[0].message.content // ""')

        if [[ -z "$content" ]]; then
            echo -e "${RED}No response from model${NC}"
            break
        fi

        # Extract the first line that starts with 'TOOL_CALL:'
        local tool_line
        tool_line=$(echo "$content" | grep -E '^TOOL_CALL:' | head -1)

        if [[ -z "$tool_line" ]]; then
            # No tool call – assume final answer
            echo -e "${BLUE}Model final answer:${NC}"
            echo "$content"
            break
        fi

        # Parse the JSON after 'TOOL_CALL:'
        local tool_json="${tool_line#TOOL_CALL:}"
        local tool_name
        tool_name=$(echo "$tool_json" | jq -r '.tool // empty')
        local tool_args
        tool_args=$(echo "$tool_json" | jq -c '.arguments // {}' 2>/dev/null || echo "{}")

        if [[ -z "$tool_name" ]]; then
            echo -e "${RED}Malformed tool call: $tool_line${NC}"
            break
        fi

        echo -e "${GREEN}  🔧 Executing: $tool_name $tool_args${NC}"

        # Execute the tool
        local result
        result=$(execute_tool "$tool_name" "$tool_args" 2>&1 || true)

        # Check for exit signal
        if [[ "$tool_name" == "exit_bridge" ]]; then
            local summary
            summary=$(echo "$tool_args" | jq -r '.summary // "Task complete"')
            echo -e "${GREEN}✅ Bridge finished: ${summary}${NC}"
            break
        fi

        # Append result to conversation history
        conversation_history="${conversation_history}\n[Tool output for ${tool_name}:]\n${result}\n"
    done

    if [[ $iteration -ge $MAX_ITERATIONS ]]; then
        echo -e "${YELLOW}⚠ Max iterations reached${NC}"
    fi

    rm -rf "$TEMP_DIR"
}

main "$@"
