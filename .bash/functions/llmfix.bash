#!/bin/bash

# Fix the last failed command using an LLM (Anthropic or OpenAI).
llmfix() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: llmfix [-i|--interactive]"
        echo "Fixes the last failed command using an LLM"
        echo "Requires: ANTHROPIC_API_KEY (preferred) or OPENAI_API_KEY"
        echo ""
        echo "Options:"
        echo "  -i, --interactive  Show detailed output and prompts"
        return 0
    fi

    local interactive=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interactive) interactive=true; shift ;;
            *) echo "Unknown option: $1"; return 1 ;;
        esac
    done

    if [[ -z "$ANTHROPIC_API_KEY" && -z "$CLAUDE_API_KEY" && -z "$OPENAI_API_KEY" ]]; then
        echo "❌ Error: no API key found"
        echo "Set ANTHROPIC_API_KEY (preferred) or OPENAI_API_KEY in ~/.bash/credentials.bash"
        return 1
    fi

    if ! command -v curl &> /dev/null; then
        echo "❌ Error: curl not found"
        return 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "❌ Error: jq not found (brew install jq / port install jq)"
        return 1
    fi

    local last_command
    last_command=$(history | tail -2 | head -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
    if [[ -z "$last_command" ]]; then
        echo "❌ Error: no command found in history"
        return 1
    fi

    if [[ "$interactive" == true ]]; then
        echo "🔍 Analyzing command: $last_command"
        echo "🤖 Asking the model..."
    fi

    local prompt="I ran this command in the terminal and it failed. Please:
1. Identify what's wrong with the command
2. Provide the corrected command
3. Give a brief explanation of the issue

Failed command: $last_command

Please respond in this exact format:
ISSUE: [brief description of what was wrong]
FIXED_COMMAND: [the corrected command]
EXPLANATION: [brief explanation of the fix]"

    local content=""
    local anthropic_key="${ANTHROPIC_API_KEY:-$CLAUDE_API_KEY}"
    if [[ -n "$anthropic_key" ]]; then
        content=$(_llmfix_call_anthropic "$anthropic_key" "$prompt")
    elif [[ -n "$OPENAI_API_KEY" ]]; then
        content=$(_llmfix_call_openai "$OPENAI_API_KEY" "$prompt")
    fi

    if [[ -z "$content" ]]; then
        echo "❌ Error: no response from LLM"
        return 1
    fi

    local issue fixed_command explanation
    issue=$(echo "$content" | grep "^ISSUE:" | sed 's/^ISSUE: //')
    fixed_command=$(echo "$content" | grep "^FIXED_COMMAND:" | sed 's/^FIXED_COMMAND: //')
    explanation=$(echo "$content" | grep "^EXPLANATION:" | sed 's/^EXPLANATION: //')

    if [[ "$interactive" == true ]]; then
        echo ""
        echo "📋 Analysis:"
        [[ -n "$issue" ]]        && echo "❌ Issue: $issue"
        if [[ -n "$fixed_command" ]]; then
            echo "✅ Fixed command: $fixed_command"
            echo ""
            echo "💡 To run the fixed command, copy and paste it above."
        fi
        [[ -n "$explanation" ]]  && echo "" && echo "📚 Explanation: $explanation"
        echo ""
    else
        if [[ -n "$fixed_command" ]]; then
            [[ -n "$explanation" ]] && echo "# $explanation"
            echo ""
            echo "$fixed_command"
        else
            echo "❌ Could not fix the command"
            return 1
        fi
    fi
}

_llmfix_call_anthropic() {
    local key="$1" prompt="$2"
    local payload
    payload=$(jq -n \
        --arg model "claude-haiku-4-5-20251001" \
        --arg content "$prompt" \
        --argjson max_tokens 400 \
        '{
            model: $model,
            max_tokens: $max_tokens,
            messages: [{role: "user", content: $content}]
        }')

    local response
    response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $key" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -d "$payload") || return 1
    echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null
}

_llmfix_call_openai() {
    local key="$1" prompt="$2"
    local payload
    payload=$(jq -n \
        --arg model "gpt-4o-mini" \
        --arg content "$prompt" \
        --argjson max_tokens 400 \
        --argjson temperature 0.3 \
        '{
            model: $model,
            messages: [{role: "user", content: $content}],
            max_tokens: $max_tokens,
            temperature: $temperature
        }')

    local response
    response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $key" \
        -H "Content-Type: application/json" \
        -d "$payload") || return 1
    echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null
}
