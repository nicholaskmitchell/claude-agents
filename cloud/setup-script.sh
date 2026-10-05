#!/bin/bash
# Setup script for a Claude Code cloud environment: paste it into the environment's
# "Setup script" field. It installs the agents and the delegation rules from
# https://github.com/nicholaskmitchell/claude-agents into the VM's ~/.claude.
#
# rev: 1
# The environment runs this script again only when its text changes, or after about a week.
# Change the number above to pick up changes to the repository straight away.

set +e +u   # whatever options bash was started with, this script has to reach "exit 0"

if [[ $(id -u) != 0 && ${CLAUDE_CODE_REMOTE:-} != true ]]; then
    echo "claude-agents: this script is for a cloud environment; nothing changed" >&2
    exit 0
fi

repo=nicholaskmitchell/claude-agents
git_url=${CA_GIT_URL:-https://github.com/$repo.git}
tar_url=${CA_TAR_URL:-https://codeload.github.com/$repo/tar.gz/refs/heads/main}
raw_url=${CA_RAW_URL:-https://raw.githubusercontent.com/$repo/main}
cfg=${CLAUDE_CONFIG_DIR:-${HOME:-/root}/.claude}
why=
tmp=$(mktemp -d 2>/dev/null) || tmp=
src=$tmp/src

# Every network command is bounded and nothing may prompt: an environment build that passes five
# minutes is thrown away and its sessions stall. A route is not started after 150 seconds.
get() { ((SECONDS < 150)) && curl -fsSL --connect-timeout 10 --max-time 20 "$@"; }
usable() { [[ $(head -n 1 "$src/cloud/install.sh" 2>/dev/null) == '#!'* ]]; }

# three routes to the same files, because which of them a cloud VM allows is not documented
fetch() {
    local f
    GIT_TERMINAL_PROMPT=0 timeout -k 5 45 git clone -q --depth 1 "$git_url" "$src" </dev/null
    why+=" git=$?"; usable && return
    rm -rf "$src"; mkdir -p "$src"
    get "$tar_url" | tar -xz -C "$src" --strip-components=1 2>/dev/null
    why+=" tarball=${PIPESTATUS[0]}/${PIPESTATUS[1]}"; usable && return
    rm -rf "$src"; mkdir -p "$src"
    get "$raw_url/cloud/files.txt" -o "$tmp/files.txt"; why+=" raw=$?"
    [[ -s $tmp/files.txt ]] || return 1
    while read -r f || [[ -n $f ]]; do
        f=${f%$'\r'}
        [[ -n $f ]] || continue
        # a manifest line is a plain relative path; anything else means this is not the manifest
        [[ $f =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ && $f != *..* ]] || { why+=" raw-manifest=bad"; return 1; }
        mkdir -p "$src/$(dirname "$f")"
        get "$raw_url/$f" -o "$src/$f" || { why+=" raw:$f=$?"; return 1; }
    done < "$tmp/files.txt"
    usable || { why+=" raw-tree=unusable"; return 1; }
}

ok=0
if [[ -z $tmp ]]; then
    why=" no-temporary-directory"
elif fetch; then
    bash "$src/cloud/install.sh" && ok=1 || why+=" install=$?"
fi
if ((!ok)); then
    # the environment caches this result, so leave a note that every session will see
    mkdir -p "$cfg/rules"
    cat > "$cfg/rules/claude-agents-setup-failed.md" <<EOF
The claude-agents setup script failed when this cloud environment was built (exit codes:${why:- not recorded}),
so the Explore, test-runner, implementer and reviewer agents and the delegation rules may be missing here.
If you are the main agent of the session, tell the user this once, in your first reply, and say that
changing the "rev:" line of the environment's setup script makes the environment run it again. Then
carry on with what the user asked. Do not try to repair the setup yourself, and do not write anything
into ~/.claude. If you are a subagent, ignore this note.
EOF
    echo "claude-agents: setup failed (exit codes:${why:- not recorded}); sessions will be told" >&2
fi
[[ -n $tmp ]] && rm -rf "$tmp"
exit 0
