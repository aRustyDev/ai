
claude:
    echo "TODO: Setup repo for claude code integration, using .ai/* contents"

opencode:
    echo "TODO: Setup repo for OpenCode integration, using .ai/* contents"

zed:
    echo "TODO: Setup repo for zed agent integration, using .ai/* contents"

vscode:
    echo "TODO: Setup repo for vscode integration, using .ai/* contents"

windsurf:
    echo "TODO: Setup repo for windsurf agent integration, using .ai/* contents"

cursor:
    echo "TODO: Setup repo for cursor agent integration, using .ai/* contents"

mcp-tools:
    echo "TODO: Setup mcp-tools for repo"

sitemap root:
    echo "TODO: Generate sitemap for repo"
    which("tree") -H '.' \
            -L 1 \
            --noreport \
            --houtro "" \
            --dirsfirst \
            --charset utf-8 \
            --ignore-case \
            --timefmt '%d-%b-%Y %H:%M' \
            -I "index.html" \
            -T 'AI Contexts' \
            -s -D \
            -P "*.zip|*.gz" \
            -o index.html
