set unstable := true

root := `git rev-parse --show-toplevel`
just_dir := justfile_directory()
xdg_config := env("XDG_CONFIG_HOME", env("HOME") + "/.config")
mcp_root := env("HOME") + "/repos" + "/mcp"
claude_desktop_config := env("HOME") + "/Library/Application Support/Claude/claude_desktop_config.json"
claude_code_global_config := env("HOME") + "/.claude/settings.json"
claude_code_project_config := root + "/.claude/settings.json"
zed_global_config := env("HOME") + "/.config/zed/settings.json"
zed_project_config := root + "/.zed/settings.json"

# JQ Queries

mcp_env_string := '$json | if .env != null then ([.env | to_entries[] | "--env \(.value)"] | join(" ")) else "" end'
mcp_arg_string := '$json | if .args != null then (.args | join(" ")) else "" end'
transport_type := '$json | .type'
transport_url := '$json | .url'
mcp_command := '$json | .command'
transport := '$json | .transport'
gemini := '. | $key | .repo'
mcp := '. | $key | del(.transport) | del(.repo)'

config-all-ai-tools mcptool: (claude-desktop mcptool) (zed mcptool) (claude-code mcptool)

hydrate file:
    #!/usr/bin/env bash
    json=$(yq --output-format json '.' "{{ just_dir }}/{{ file }}")
    injected=$(echo "$json" | op inject)
    export MCP_ROOT="{{ mcp_root }}"
    output=$(echo "$injected" | envsubst)
    echo "$output"

zed key scope="global":
    #!/usr/bin/env bash
    if [[ "{{ which("zed") }}" != "" ]]; then
        cfg="{{ if scope == 'global' { zed_global_config } else { zed_project_config } }}" # Pick Config File
        json=$(just hydrate "mcp.yaml" | jq --arg key "{{ key }}" '{{ mcp }}') # Extract Map from YAML
        mcp_json="{\"{{ key }}\": $json}" # JSON Object to add to Zed Config
        clean_zed_config=$(sed -e '\|^[[:space:]]*//.*$|d' -e 's|//.*||g' "$cfg") # Clean Config
        jq -n --argjson mcp "$mcp_json" --argjson cfg "$clean_zed_config" '$cfg | .context_servers += $mcp' "$cfg" | sponge "$cfg"
    fi

claude-desktop key:
    #!/usr/bin/env bash
    if [[ -f "{{ claude_desktop_config }}" ]]; then
        manifest="$(just hydrate "mcp.yaml")"
        json=$(jq -r -n --arg key "{{ key }}" --argjson json "$manifest" '$json | to_entries[] | select(.key == $key) | .value | del(.transport) | del(.repo) | if (. | keys != []) then { {{ key }}: .} else "null" end')
        if [[ "$json" != "null" ]]; then
            jq --argjson mcp "$json" '.mcpServers += $mcp' "{{ claude_desktop_config }}" | sponge "{{ claude_desktop_config }}"
        fi
    fi

docker-mcp-toolkit key:
    #!/usr/bin/env bash
    if [[ "{{ which("docker-desktop") }}" != "" ]]; then
        docker mcp secret set GITHUB.PERSONAL_ACCESS_TOKEN=op://developer/github/docker-mcp-toolkit/token
        echo "TODO"
    fi

claude-code key:
    #!/usr/bin/env bash
    if [[ "{{ which("claude") }}" != "" ]]; then
        manifest="$(just hydrate "mcp.yaml")"
        json="$(jq -n --arg key "{{ key }}" --argjson json "$manifest" '$json | to_entries[] | select(.key == $key) | .value')"
        transport="$(jq -n --argjson json "$json" '$json | if .transport != null then .transport else "null" end')"
        if [[ "$transport" != "null" ]]; then
            method="$(jq -r -n --argjson json "$transport" '{{ transport_type }}')"
            if [[ "$method" == "stdio" ]]; then
                envs="$(jq -n --argjson json "$json" '{{ mcp_env_string }}')"
                args="$(jq -n --argjson json "$json" '{{ mcp_arg_string }}')"
                cmd="$(jq -n --argjson json "$json" '{{ mcp_command }}')"
                claude mcp add --transport stdio "{{ key }}" $envs -- $cmd $args
            elif [[ "$method" == "http" || "$method" == "sse" ]]; then
                url=$(jq -r -n --argjson json "$transport" '$json | .url')
                claude mcp add --transport $method "{{ key }}" "$url"
            else
                echo "Method not supported"
            fi
        else
            echo "Transport not specified"
        fi
    fi

gemini-cli key:
    #!/usr/bin/env bash
    if [[ "{{ which("gemini") }}" != "" ]]; then
        json=$(just hydrate "mcp.yaml" | jq '{{ gemini }}')
        gemini extensions install https://github.com/huggingface/hf-mcp-server
    fi

claud-hook key scope="global":
    #!/usr/bin/env bash
    if [[ "{{ which("claude") }}" != "" ]]; then
        cfg="{{ if scope == 'global' { claude_code_global_config } else { claude_code_project_config } }}" # Pick Config File
        json=$(just hydrate "mcp.yaml" | jq --arg key "{{ key }}" '{{ mcp }}') # Extract Map from YAML
        claude mcp add --transport http "{{ key }}" https://huggingface.co/mcp
    fi
    volta install tdd-guard
    # cargo install tdd-guard-rust
    # go install github.com/nizos/tdd-guard/reporters/go/cmd/tdd-guard-go@latest
    # pip install tdd-guard-pytest
