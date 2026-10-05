#!/usr/bin/env bash
# Offline tests for cloud/install.sh, cloud/setup-script.sh, cloud/files.txt and bin/check-setup.
# Everything happens in a temporary directory; the real ~/.claude is never touched.
#
#   cloud/test.sh
#
# Prints one line per case and a summary; exits 1 if any case failed.
set -u

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
# the user's own git configuration (signing, templates) must not reach the fixtures
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

agent_files=("$ROOT"/agents/*.md)
N=${#agent_files[@]}
nowhere_path=$T/nowhere
nowhere_url=file://$T/nowhere

# run a command with the cloud variables removed; later NAME=value arguments set them again
clean() { env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_SESSION_ID "$@"; }
# output (both streams) and exit status of a command, in $out and $rc
run() { out=$("$@" 2>&1); rc=$?; }
# standard error alone, in $err and also in $out
run_err() { err=$("$@" 2>&1 >/dev/null); rc=$?; out=$err; }

# assertions: the first one that fails in a case is the one reported
msg=
fail() { [[ -n $msg ]] || msg=$1; }
expect_rc() { [[ $rc == "$1" ]] || fail "exit status $rc, expected $1; output: ${out:0:300}"; }
expect_nonzero() { [[ $rc != 0 ]] || fail "exit status 0, expected non-zero; output: ${out:0:300}"; }
expect_file() { [[ -e $1 ]] || fail "$1 does not exist"; }
expect_absent() { [[ ! -e $1 && ! -L $1 ]] || fail "$1 exists"; }
expect_nonempty() { [[ -s $1 ]] || fail "$1 is missing or empty"; }
expect_contains() { [[ $1 == *"$2"* ]] || fail "missing \"$2\" in: ${1:0:300}"; }
expect_lacks() { [[ $1 != *"$2"* ]] || fail "unexpected \"$2\" in: ${1:0:300}"; }
expect_matches() { grep -Eq -- "$2" <<< "$1" || fail "no line matches \"$2\" in: ${1:0:300}"; }
expect_equal() { [[ $1 == "$2" ]] || fail "$3: got \"$1\", expected \"$2\""; }
expect_same_file() { cmp -s "$1" "$2" || fail "$1 differs from $2"; }

# the agents folder holds exactly the repository's agent files, byte for byte
expect_agents() {
    local want got f
    want=$(printf '%s\n' "${agent_files[@]##*/}" | sort)
    got=$(ls -A "$1" 2>/dev/null | sort)
    expect_equal "$got" "$want" "files in $1"
    for f in "${agent_files[@]}"; do expect_same_file "$f" "$1/${f##*/}"; done
}

# a git repository in $1 made from what is already there
make_repo() {
    git -C "$1" init -q -b main &&
        git -C "$1" add -A &&
        git -C "$1" -c user.name=test -c user.email=test@example.invalid commit -q -m fixture
}

# fixtures
mkdir -p "$T/repo" "$T/broken"
cp -r "$ROOT/agents" "$ROOT/bin" "$ROOT/cloud" "$ROOT/delegation.md" "$ROOT/mirror.md" "$T/repo/"
make_repo "$T/repo"
git -C "$T/repo" archive --format=tar.gz --prefix=claude-agents-main/ -o "$T/repo.tar.gz" HEAD
echo broken > "$T/broken/README.md"
make_repo "$T/broken"

# copies of the repository's files with one change each; a proxy's error page stands in for a file
PAGE='<!DOCTYPE html><html><body>blocked</body></html>'
copy_tree() {
    mkdir -p "$1"
    cp -r "$T/repo/agents" "$T/repo/bin" "$T/repo/cloud" "$T/repo/delegation.md" "$T/repo/mirror.md" "$1/"
}
copy_tree "$T/bad-agent"; echo "$PAGE" > "$T/bad-agent/agents/reviewer.md"
copy_tree "$T/bad-rules"; echo "$PAGE" > "$T/bad-rules/delegation.md"
copy_tree "$T/bad-mirror"; echo "$PAGE" > "$T/bad-mirror/mirror.md"
copy_tree "$T/no-mirror"; rm "$T/no-mirror/mirror.md"
copy_tree "$T/bad-settings"; echo "$PAGE" > "$T/bad-settings/cloud/settings.json"
copy_tree "$T/nonl"; printf '%s' "$(cat "$T/repo/cloud/files.txt")" > "$T/nonl/cloud/files.txt"
copy_tree "$T/evil"; echo 'agents/../escaped.txt' >> "$T/evil/cloud/files.txt"
echo bait > "$T/evil/escaped.txt"
# a jq that always fails
mkdir -p "$T/shim"
printf '%s\n' '#!/bin/sh' 'exit 127' > "$T/shim/jq"
chmod +x "$T/shim/jq"

# A. cloud/install.sh

c_A1() {
    run clean HOME="$T/a1h" bash "$ROOT/cloud/install.sh" --home "$T/a1"
    expect_rc 0
    expect_agents "$T/a1/agents"
    expect_same_file "$ROOT/delegation.md" "$T/a1/rules/delegation.md"
    expect_same_file "$ROOT/mirror.md" "$T/a1/rules/mirror.md"
    expect_equal "$(ls -A "$T/a1/rules" 2>&1)" "$(printf '%s\n' delegation.md mirror.md)" "files in $T/a1/rules"
    expect_equal "$(jq -S . "$T/a1/settings.json" 2>&1)" "$(jq -S . "$ROOT/cloud/settings.json")" "settings.json"
    local status
    status=$(cat "$T/a1/claude-agents.status" 2>&1)
    [[ $status != *$'\n'* ]] || fail "status file has more than one line"
    [[ $status == "ok commit="* ]] || fail "status line does not start with \"ok commit=\": $status"
    expect_contains "$status" " agents=$N "
}

c_A2() {
    mkdir -p "$T/a2"
    echo '{"theme":"dark","modelSettings":{"claude-opus-5-5":{"effortLevel":"high"}}}' > "$T/a2/settings.json"
    run clean HOME="$T/a2h" bash "$ROOT/cloud/install.sh" --home "$T/a2"
    expect_rc 0
    expect_equal "$(jq -r .theme "$T/a2/settings.json" 2>&1)" dark ".theme"
    expect_equal "$(jq -r '.modelSettings["claude-opus-5-5"].effortLevel' "$T/a2/settings.json" 2>&1)" high "opus effort"
    expect_equal "$(jq -r '.modelSettings["claude-sonnet-5-5"].effortLevel' "$T/a2/settings.json" 2>&1)" xhigh "sonnet effort"
}

c_A3() {
    mkdir -p "$T/a3"
    printf 'not json' > "$T/a3/settings.json"
    run clean HOME="$T/a3h" bash "$ROOT/cloud/install.sh" --home "$T/a3"
    expect_rc 0
    expect_equal "$(cat "$T/a3/settings.json")" "not json" "settings.json"
    expect_contains "$(cat "$T/a3/claude-agents.status" 2>&1)" "settings.json left alone"
    expect_file "$T/a3/agents/Explore.md"
}

c_A4() {
    local first
    run clean HOME="$T/a4h" bash "$ROOT/cloud/install.sh" --home "$T/a4"
    expect_rc 0
    first=$(jq -S . "$T/a4/settings.json" 2>&1)
    run clean HOME="$T/a4h" bash "$ROOT/cloud/install.sh" --home "$T/a4"
    expect_rc 0
    expect_equal "$(jq -S . "$T/a4/settings.json" 2>&1)" "$first" "settings.json after the second run"
    expect_agents "$T/a4/agents"
}

c_A5() {
    mkdir -p "$T/a5/rules"
    echo stale > "$T/a5/rules/claude-agents-setup-failed.md"
    run clean HOME="$T/a5h" bash "$ROOT/cloud/install.sh" --home "$T/a5"
    expect_rc 0
    expect_absent "$T/a5/rules/claude-agents-setup-failed.md"
}

c_A6() {
    mkdir -p "$T/a6" "$T/a6-target"
    ln -s "$T/a6-target" "$T/a6/agents"
    run clean HOME="$T/a6h" bash "$ROOT/cloud/install.sh" --home "$T/a6"
    expect_nonzero
    [[ -z $(ls -A "$T/a6-target") ]] || fail "$T/a6-target is not empty"
    expect_absent "$T/a6/rules"
    expect_absent "$T/a6/claude-agents.status"
}

c_A7() {
    [[ $(id -u) != 0 ]] || return 77
    run clean HOME="$T/a7" bash "$ROOT/cloud/install.sh"
    expect_nonzero
    expect_absent "$T/a7/.claude"
}

c_A8() {
    run clean HOME="$T/a8" CLAUDE_CODE_REMOTE=true bash "$ROOT/cloud/install.sh"
    expect_rc 0
    expect_file "$T/a8/.claude/agents/Explore.md"
}

c_A9() {
    run clean HOME="$T/a9" CLAUDE_CODE_REMOTE=true CLAUDE_CONFIG_DIR="$T/a9cfg" bash "$ROOT/cloud/install.sh"
    expect_rc 0
    expect_file "$T/a9cfg/rules/delegation.md"
    expect_file "$T/a9cfg/rules/mirror.md"
    expect_absent "$T/a9/.claude"
}

c_A10() {
    run clean HOME="$T/a10" CLAUDE_CODE_REMOTE=true bash "$ROOT/cloud/install.sh" --bogus
    expect_rc 2
    expect_absent "$T/a10/.claude"
}

c_A11() {
    run clean HOME="$T/a11h" bash "$T/bad-agent/cloud/install.sh" --home "$T/a11"
    expect_nonzero
    expect_absent "$T/a11/agents"
    expect_absent "$T/a11/claude-agents.status"
}

c_A12() {
    run clean HOME="$T/a12h" bash "$T/bad-rules/cloud/install.sh" --home "$T/a12"
    expect_nonzero
    expect_absent "$T/a12/rules"
    expect_absent "$T/a12/claude-agents.status"
}

c_A13() {
    run clean HOME="$T/a13h" bash "$T/bad-settings/cloud/install.sh" --home "$T/a13"
    expect_nonzero
    expect_absent "$T/a13/settings.json"
    expect_absent "$T/a13/agents"
}

c_A14() {
    mkdir -p "$T/a14"
    echo '{"theme":"dark"}' > "$T/a14/settings.json"
    run clean HOME="$T/a14h" PATH="$T/shim:$PATH" bash "$ROOT/cloud/install.sh" --home "$T/a14"
    expect_rc 0
    expect_equal "$(cat "$T/a14/settings.json")" '{"theme":"dark"}' "settings.json"
    expect_contains "$(cat "$T/a14/claude-agents.status" 2>&1)" "settings.json left alone"
    expect_file "$T/a14/agents/Explore.md"
}

c_A15() {
    run clean HOME="$T/a15h" bash "$T/bad-mirror/cloud/install.sh" --home "$T/a15"
    expect_nonzero
    expect_absent "$T/a15/rules"
    expect_absent "$T/a15/agents"
    expect_absent "$T/a15/claude-agents.status"
}

c_A16() {
    run clean HOME="$T/a16h" bash "$T/no-mirror/cloud/install.sh" --home "$T/a16"
    expect_nonzero
    expect_absent "$T/a16/rules"
    expect_absent "$T/a16/claude-agents.status"
}

# B. cloud/setup-script.sh: setup_run <id> <git url> <tar url> <raw url> [NAME=value...]
# The script's temporary directory is T/tmp-<id>, unless the case sets TMPDIR itself.
setup_run() {
    local id=$1 git_url=$2 tar_url=$3 raw_url=$4 arg own_tmp=1
    shift 4
    for arg in "$@"; do [[ $arg == TMPDIR=* ]] && own_tmp=0; done
    ((!own_tmp)) || mkdir -p "$T/tmp-${id,,}"
    run clean HOME="$T/$id" CLAUDE_CODE_REMOTE=true CA_GIT_URL="$git_url" CA_TAR_URL="$tar_url" \
        CA_RAW_URL="$raw_url" TMPDIR="$T/tmp-${id,,}" "$@" bash "$ROOT/cloud/setup-script.sh"
}

expect_installed() {
    expect_rc 0
    expect_agents "$1/.claude/agents"
    expect_same_file "$ROOT/mirror.md" "$1/.claude/rules/mirror.md"
    [[ $(cat "$1/.claude/claude-agents.status" 2>&1) == "ok "* ]] || fail "status file does not start with \"ok \""
    expect_absent "$1/.claude/rules/claude-agents-setup-failed.md"
}

expect_failure_note() {
    expect_nonempty "$1/.claude/rules/claude-agents-setup-failed.md"
}

# the text of the failure note
note_of() { cat "$1/.claude/rules/claude-agents-setup-failed.md" 2>&1; }

c_B1() {
    setup_run b1 "$T/repo" "$nowhere_url" "$nowhere_url"
    expect_installed "$T/b1"
}

c_B2() {
    setup_run b2 "$nowhere_path" "file://$T/repo.tar.gz" "$nowhere_url"
    expect_installed "$T/b2"
}

c_B3() {
    setup_run b3 "$nowhere_path" "$nowhere_url" "file://$T/repo"
    expect_installed "$T/b3"
}

c_B4() {
    setup_run b4 "$nowhere_path" "$nowhere_url" "$nowhere_url"
    expect_rc 0
    expect_failure_note "$T/b4"
    expect_absent "$T/b4/.claude/agents"
    expect_absent "$T/b4/.claude/claude-agents.status"
}

c_B5() {
    setup_run b5 "$T/broken" "$nowhere_url" "$nowhere_url"
    expect_rc 0
    expect_failure_note "$T/b5"
}

c_B6() {
    [[ $(id -u) != 0 ]] || return 77
    mkdir -p "$T/tmp-b6"
    run clean HOME="$T/b6" TMPDIR="$T/tmp-b6" CA_GIT_URL="$T/repo" CA_TAR_URL="$nowhere_url" CA_RAW_URL="$nowhere_url" \
        bash "$ROOT/cloud/setup-script.sh"
    expect_rc 0
    expect_absent "$T/b6/.claude"
}

c_B7() {
    mkdir -p "$T/b7tmp"
    setup_run b7 "$T/repo" "$nowhere_url" "$nowhere_url" TMPDIR="$T/b7tmp"
    expect_rc 0
    [[ -z $(ls -A "$T/b7tmp") ]] || fail "$T/b7tmp is not empty: $(ls -A "$T/b7tmp")"
}

c_B8() {
    setup_run b8 "$nowhere_path" "$nowhere_url" "file://$T/bad-agent"
    expect_rc 0
    expect_failure_note "$T/b8"
    expect_contains "$(note_of "$T/b8")" "install="
    expect_absent "$T/b8/.claude/agents"
    expect_absent "$T/b8/.claude/claude-agents.status"
}

c_B9() {
    setup_run b9 "$nowhere_path" "$nowhere_url" "file://$T/nonl"
    expect_installed "$T/b9"
    expect_file "$T/b9/.claude/settings.json"
}

c_B10() {
    mkdir -p "$T/b10tmp"
    setup_run b10 "$nowhere_path" "$nowhere_url" "file://$T/evil" TMPDIR="$T/b10tmp"
    expect_rc 0
    expect_contains "$(note_of "$T/b10")" "raw-manifest=bad"
    [[ -z $(ls -A "$T/b10tmp") ]] || fail "$T/b10tmp is not empty: $(ls -A "$T/b10tmp")"
    expect_absent "$T/b10/.claude/agents"
}

c_B11() {
    setup_run b11 "$nowhere_path" "$nowhere_url" "$nowhere_url" TMPDIR="$T/does-not-exist"
    expect_rc 0
    expect_failure_note "$T/b11"
    expect_contains "$(note_of "$T/b11")" "no-temporary-directory"
}

c_B12() {
    mkdir -p "$T/tmp-b12"
    run clean HOME="$T/b12" CLAUDE_CODE_REMOTE=true CA_GIT_URL="$nowhere_path" CA_TAR_URL="$nowhere_url" \
        CA_RAW_URL="$nowhere_url" TMPDIR="$T/tmp-b12" bash -eu "$ROOT/cloud/setup-script.sh"
    expect_rc 0
    expect_failure_note "$T/b12"
}

c_B13() {
    setup_run b13 "$nowhere_path" "$nowhere_url" "$nowhere_url"
    expect_rc 0
    expect_contains "$(note_of "$T/b13")" "git="
    expect_contains "$(note_of "$T/b13")" "tarball="
    expect_contains "$(note_of "$T/b13")" "raw="
}

c_B14() {
    setup_run b14 "$nowhere_path" "$nowhere_url" "$nowhere_url"
    expect_rc 0
    expect_contains "$(note_of "$T/b14")" ".github/workflows/sync-to-gitlab.yml"
    expect_contains "$(note_of "$T/b14")" "never push to main"
}

# C. consistency

c_C1() {
    local want got
    want=$({ printf '%s\n' "${agent_files[@]#"$ROOT"/}"; printf '%s\n' delegation.md mirror.md cloud/install.sh cloud/settings.json; } | sort)
    got=$(grep -v '^$' "$ROOT/cloud/files.txt" | sort)
    expect_equal "$got" "$want" "cloud/files.txt"
}

c_C2() {
    local f
    for f in cloud/install.sh cloud/setup-script.sh bin/sync-to-repo; do
        run bash -n "$ROOT/$f"
        [[ $rc == 0 ]] || fail "bash -n $f failed: ${out:0:300}"
    done
    run python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$ROOT/bin/check-setup"
    [[ $rc == 0 ]] || fail "bin/check-setup does not parse: ${out:0:300}"
    run jq . "$ROOT/cloud/settings.json"
    [[ $rc == 0 ]] || fail "cloud/settings.json is not JSON: ${out:0:300}"
}

c_C3() {
    local f key head
    for f in "${agent_files[@]}"; do
        [[ $(head -n 1 "$f") == --- ]] || { fail "${f##*/} does not start with ---"; continue; }
        head=$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "$f")
        for key in name model effort; do
            grep -q "^$key:" <<< "$head" || fail "${f##*/} has no $key: line in its frontmatter"
        done
    done
}

c_C4() {
    grep -q '^## Delegation' "$ROOT/delegation.md" || fail "delegation.md has no \"## Delegation\" heading"
    grep -q '^## Repositories mirrored from GitLab' "$ROOT/mirror.md" ||
        fail "mirror.md has no \"## Repositories mirrored from GitLab\" heading"
}

# D. bin/check-setup, against a fabricated configuration directory

d1=$T/d1
mkdir -p "$d1/projects/p/S1/subagents/workflows/wf_1" "$d1/agents" "$T/d4"
{
    echo '{"type":"assistant","effort":"xhigh","message":{"id":"m1","model":"model-main","content":[]}}'
    echo '{"type":"assistant","effort":"xhigh","message":{"id":"m1","model":"model-main","content":[]}}'
    echo '{"type":"assistant","effort":"xhigh","message":{"id":"m2","model":"model-main","content":[]}}'
} > "$d1/projects/p/S1.jsonl"
echo '{"type":"assistant","effort":"medium","message":{"id":"s1","model":"model-sub","content":[]}}' \
    > "$d1/projects/p/S1/subagents/agent-a.jsonl"
echo '{"agentType":"Explore"}' > "$d1/projects/p/S1/subagents/agent-a.meta.json"
echo '{"type":"assistant","effort":"low","message":{"id":"w1","model":"model-wf","content":[]}}' \
    > "$d1/projects/p/S1/subagents/workflows/wf_1/agent-b.jsonl"
echo '{"agentType":"workflow-subagent"}' > "$d1/projects/p/S1/subagents/workflows/wf_1/agent-b.meta.json"
: > "$d1/agents/x.md"
echo "ok commit=abc agents=1 date=x" > "$d1/claude-agents.status"
echo '{"type":"assistant","effort":"high","message":{"id":"o1","model":"model-other","content":[]}}' \
    > "$d1/projects/p/A2.jsonl"
touch -d "2 hours ago" "$d1/projects/p/S1.jsonl"

c_D1() {
    local want
    run clean HOME="$T/d1home" CLAUDE_CONFIG_DIR="$d1" "$ROOT/bin/check-setup" S1
    expect_rc 0
    for want in "model-main @ xhigh x2" "Explore" "model-sub @ medium x1" "wf:workflow-subagent" \
        "model-wf @ low x1" "ok commit=abc"; do
        expect_contains "$out" "$want"
    done
    expect_lacks "$out" "model-other"
    expect_matches "$out" "wf:workflow-subagent +model-wf @ low x1"
}

c_D2() {
    run clean HOME="$T/d1home" CLAUDE_CONFIG_DIR="$d1" CLAUDE_CODE_SESSION_ID=S1 "$ROOT/bin/check-setup"
    expect_rc 0
    expect_contains "$(grep '^session' <<< "$out")" S1
    expect_lacks "$out" "model-other"
}

c_D3() {
    run clean HOME="$T/d1home" CLAUDE_CONFIG_DIR="$d1" "$ROOT/bin/check-setup"
    expect_rc 0
    expect_contains "$(grep '^session' <<< "$out")" A2
    expect_contains "$out" "model-other @ high x1"
}

c_D4() {
    run_err clean HOME="$T/d1home" CLAUDE_CONFIG_DIR="$T/d4" "$ROOT/bin/check-setup"
    expect_nonzero
    expect_contains "$err" "no session transcripts"
}

c_D5() {
    run_err clean HOME="$T/d1home" CLAUDE_CONFIG_DIR="$d1" "$ROOT/bin/check-setup" NOPE
    expect_nonzero
    expect_contains "$err" "no session transcripts for NOPE"
}

c_D6() {
    mkdir -p "$T/d6/projects/p"
    echo '{"type":"assistant","effort":"xhigh","message":{"id":"m1","model":"model-main","content":[]}}' \
        > "$T/d6/projects/p/S1.jsonl"
    printf 'not json' > "$T/d6/settings.json"
    run clean HOME="$T/d6home" CLAUDE_CONFIG_DIR="$T/d6" "$ROOT/bin/check-setup" S1
    expect_rc 0
    expect_contains "$out" "settings.json is not valid JSON"
}

c_D7() {
    mkdir -p "$T/d7/projects/p"
    echo '{"type":"assistant","effort":"xhigh","message":{"id":"m1","model":"model-main","content":[]}}' \
        > "$T/d7/projects/p/S1.jsonl"
    echo '[]' > "$T/d7/settings.json"
    run clean HOME="$T/d7home" CLAUDE_CONFIG_DIR="$T/d7" "$ROOT/bin/check-setup" S1
    expect_rc 0
    expect_contains "$out" "settings.json is not a JSON object"
}

c_D8() {
    mkdir -p "$T/d8/projects/p"
    {
        echo '{"type":"assistant","effort":"xhigh","message":{"id":"m1","model":"model-main","content":[]}}'
        echo '{"type":"assistant","message":{"id":"z1","model":"<synthetic>","content":[]}}'
    } > "$T/d8/projects/p/S1.jsonl"
    run clean HOME="$T/d8home" CLAUDE_CONFIG_DIR="$T/d8" "$ROOT/bin/check-setup" S1
    expect_rc 0
    expect_contains "$out" "model-main @ xhigh x1"
    expect_lacks "$out" "synthetic"
}

# run the cases in order; one that fails does not stop the rest
declare -A names=(
    [A1]="fresh install"
    [A2]="merge keeps existing settings"
    [A3]="invalid settings left alone"
    [A4]="second run changes nothing"
    [A5]="stale failure note removed"
    [A6]="refuses a linked agents folder"
    [A7]="refuses a workstation"
    [A8]="runs when CLAUDE_CODE_REMOTE is true"
    [A9]="honours CLAUDE_CONFIG_DIR"
    [A10]="unknown option is a usage error"
    [A11]="rejects a page in place of an agent file"
    [A12]="rejects a page in place of the rules"
    [A13]="rejects a page in place of the settings fragment"
    [A14]="a failing jq leaves existing settings alone"
    [A15]="rejects a page in place of the mirror rules"
    [A16]="refuses a tree without the mirror rules"
    [B1]="git route"
    [B2]="tarball route"
    [B3]="raw route"
    [B4]="every route fails"
    [B5]="fetched tree has no installer"
    [B6]="does nothing on a workstation"
    [B7]="temporary directory removed"
    [B8]="raw route refuses a poisoned file"
    [B9]="manifest without a final newline"
    [B10]="manifest line outside the tree is refused"
    [B11]="no temporary directory"
    [B12]="started as bash -eu"
    [B13]="failure note names each route"
    [B14]="failure note carries the mirror rule"
    [C1]="manifest matches the files"
    [C2]="scripts parse"
    [C3]="agent files have their frontmatter"
    [C4]="rules files have their headings"
    [D1]="reports a named session"
    [D2]="uses CLAUDE_CODE_SESSION_ID"
    [D3]="falls back to the newest session"
    [D4]="no transcripts is an error"
    [D5]="an unknown session argument is an error"
    [D6]="invalid settings are reported"
    [D7]="settings that are not an object are reported"
    [D8]="synthetic lines are not counted"
)
passed=0 failed=0 skipped=0
for id in A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 A11 A12 A13 A14 A15 A16 B1 B2 B3 B4 B5 B6 B7 B8 B9 B10 B11 B12 B13 B14 \
    C1 C2 C3 C4 D1 D2 D3 D4 D5 D6 D7 D8; do
    msg=
    "c_$id"
    status=$?
    if ((status == 77)); then
        echo "skip $id ${names[$id]}"
        skipped=$((skipped + 1))
    elif [[ -n $msg ]]; then
        echo "FAIL $id ${names[$id]}"
        echo "     $msg"
        failed=$((failed + 1))
    else
        echo "ok   $id ${names[$id]}"
        passed=$((passed + 1))
    fi
done
echo "$passed passed, $failed failed, $skipped skipped"
((failed == 0))
