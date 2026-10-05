#!/usr/bin/env bash
# Install the agents, the delegation rules and the effort defaults into Claude Code's
# configuration directory. This is for a cloud session's VM, where cloud/setup-script.sh
# runs it when the environment is built. A workstation uses the links in the README instead.
#
#   cloud/install.sh [--home <dir>]
#
# <dir> is the configuration directory to install into; the default is $CLAUDE_CONFIG_DIR,
# or ~/.claude. Without --home the script runs only as root or with CLAUDE_CODE_REMOTE=true,
# so that starting it by mistake on a workstation changes nothing.
set -euo pipefail

src=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd -P)
home=${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}
cfg=${CLAUDE_CONFIG_DIR:-$home/.claude}
forced=0
while (($#)); do
    case $1 in
        --home) cfg=${2:?--home needs a directory}; forced=1; shift 2 ;;
        *) echo "usage: cloud/install.sh [--home <dir>]" >&2; exit 2 ;;
    esac
done
if ((!forced)) && [[ $(id -u) != 0 && ${CLAUDE_CODE_REMOTE:-} != true ]]; then
    echo "not a cloud session (not root, and CLAUDE_CODE_REMOTE is not true): nothing changed" >&2
    exit 1
fi
# the README's local setup makes agents a link into a checkout; copying there would write into it
if [[ -L $cfg/agents || -L $cfg/rules ]]; then
    echo "$cfg: agents or rules is a symbolic link, so this is a workstation setup: nothing changed" >&2
    exit 1
fi

agents=("$src"/agents/*.md)
[[ -f ${agents[0]} && -f $src/delegation.md && -f $src/cloud/settings.json ]] ||
    { echo "$src: agents/*.md, delegation.md or cloud/settings.json is missing" >&2; exit 1; }
# A proxy can answer a blocked request with status 200 and an error page, which curl -f accepts.
# Check that each file is what it should be before anything is copied.
for f in "${agents[@]}"; do
    [[ $(head -n 1 "$f") == ---* ]] && grep -q '^name: ' "$f" ||
        { echo "$f: not an agent file (no frontmatter): nothing changed" >&2; exit 1; }
done
grep -q '^## Delegation' "$src/delegation.md" ||
    { echo "$src/delegation.md: not the delegation rules: nothing changed" >&2; exit 1; }
fragment=$(tr -d ' \t\r\n' < "$src/cloud/settings.json")
[[ $fragment == '{'*'}' ]] ||
    { echo "$src/cloud/settings.json: not a JSON object: nothing changed" >&2; exit 1; }

mkdir -p "$cfg/agents" "$cfg/rules"
cp "${agents[@]}" "$cfg/agents/"
cp "$src/delegation.md" "$cfg/rules/delegation.md"
rm -f "$cfg/rules/claude-agents-setup-failed.md"

# effort defaults: merged into settings.json, so that whatever is already there is kept
settings=$cfg/settings.json note=
if [[ ! -e $settings ]]; then
    cp "$src/cloud/settings.json" "$settings"
elif merged=$(jq -s '.[0] * .[1]' "$settings" "$src/cloud/settings.json" 2>/dev/null); then
    printf '%s\n' "$merged" > "$settings"
else
    note=" (settings.json left alone: jq is missing or the file is not JSON)"
fi

# a tarball or raw download has no history; do not let git find some enclosing repository instead
commit=unknown
if [[ -e $src/.git ]]; then commit=$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo unknown); fi
printf 'ok commit=%s agents=%d date=%s%s\n' "$commit" "${#agents[@]}" "$(date -u +%Y-%m-%dT%H:%MZ)" "$note" |
    tee "$cfg/claude-agents.status"
