#!/bin/bash

# Function to generate commit message using LLM
dot-commit-llm() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-commit-llm [git_commit_options]"
        echo "Generates commit message using LLM based on git diff"
        echo "Requires OPENAI_API_KEY, ANTHROPIC_API_KEY, or CLAUDE_API_KEY"
        return 0
    fi

    local commit_message=""
    local diff_output=""

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    # Check if there are staged changes
    if ! git diff --cached --quiet; then
        diff_output=$(git diff --cached)
    elif ! git diff --quiet; then
        # If no staged changes, check for unstaged changes
        diff_output=$(git diff)
    else
        echo "No changes to commit"
        return 1
    fi

    # Check if we have an LLM API key (you can set this in credentials.bash)
    if [[ -z "$OPENAI_API_KEY" && -z "$ANTHROPIC_API_KEY" && -z "$CLAUDE_API_KEY" ]]; then
        echo "Warning: No LLM API key found. Set OPENAI_API_KEY, ANTHROPIC_API_KEY, or CLAUDE_API_KEY in credentials.bash"
        echo "Proceeding with manual commit message..."
        git commit "$@"
        return 0
    fi

    # Generate commit message using available LLM
    if [[ -n "$OPENAI_API_KEY" ]]; then
        commit_message=$(dot-generate-commit-openai "$diff_output")
    elif [[ -n "$ANTHROPIC_API_KEY" ]]; then
        commit_message=$(dot-generate-commit-anthropic "$diff_output")
    elif [[ -n "$CLAUDE_API_KEY" ]]; then
        commit_message=$(dot-generate-commit-claude "$diff_output")
    fi

    # If we got a commit message, use it
    if [[ -n "$commit_message" ]]; then
        echo "$commit_message"
        echo ""
        read -rp "Use this commit message? (y/n/e to edit): " response
        case $response in
            [Yy]* )
                git commit -m "$commit_message" "$@"
                ;;
            [Ee]* )
                git commit -e -m "$commit_message" "$@"
                ;;
            * )
                echo "Aborted. Use 'git commit' manually."
                ;;
        esac
    else
        echo "Failed to generate commit message. Falling back to manual commit."
        git commit "$@"
    fi
}

# Helper function for OpenAI API
dot-generate-commit-openai() {
    local diff_output="$1"
    local prompt="Based on the following git diff, write a concise, descriptive commit message in conventional commit format (type(scope): description). Focus on what changed and why:

$diff_output"

    # Create JSON payload using jq to properly escape everything
    local json_payload
    json_payload=$(jq -n \
        --arg model "gpt-3.5-turbo" \
        --arg role "user" \
        --arg content "$prompt" \
        --argjson max_tokens 100 \
        --argjson temperature 0.3 \
        '{
            model: $model,
            messages: [{
                role: $role,
                content: $content
            }],
            max_tokens: $max_tokens,
            temperature: $temperature
        }')

    local response
    response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload")

    # Extract the content
    local content
    content=$(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null)

    if [[ "$content" == "null" || -z "$content" ]]; then
        # Try without jq as fallback
        content=$(echo "$response" | grep -o '"content":"[^"]*"' | sed 's/"content":"//' | sed 's/"$//')
    fi

    echo "$content"
}

# Helper function for Anthropic API
dot-generate-commit-anthropic() {
    local diff_output="$1"
    local prompt="Based on the following git diff, write a concise, descriptive commit message in conventional commit format (type(scope): description). Focus on what changed and why. Keep it under 72 characters for the first line:

$diff_output"

    curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"claude-3-sonnet-20240229\",
            \"max_tokens\": 100,
            \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}]
        }" | jq -r '.content[0].text' 2>/dev/null | head -n1
}

# Helper function for Claude API (if different from Anthropic)
dot-generate-commit-claude() {
    # Use the same as Anthropic since they're the same company
    dot-generate-commit-anthropic "$1"
}
