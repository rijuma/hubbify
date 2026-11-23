#!/usr/bin/env bash
# Checks the shared server config recipes against a stand-in for the 1Password CLI.
# Run from the repo root: bash scripts/server-config.test.sh
# shellcheck disable=SC2016
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Two checkouts stand for two people; the vault directory stands for 1Password.
for checkout in ana ben; do
  mkdir -p "$work/$checkout/servers"
  cp -r "$repo_root/justfile" "$repo_root/scripts" "$work/$checkout/"
  cp -r "$repo_root/servers/_template" "$work/$checkout/servers/"
done
export OP_STUB_VAULTS="$work/vaults"
mkdir -p "$OP_STUB_VAULTS/team" "$work/bin"
cat >"$work/bin/op" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${OP_STUB_SIGNED_IN:-1}" = 1 ] || { echo "[ERROR] You are not currently signed in." >&2; exit 1; }
kind=$1 action=$2; shift 2
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) vault=$2; shift 2 ;;
    --title) title=$2; shift 2 ;;
    --out-file) out=$2; shift 2 ;;
    --force) shift ;;
    *) positional+=("$1"); shift ;;
  esac
done
case "$kind $action" in
  "vault get") [ -d "$OP_STUB_VAULTS/${positional[0]}" ] ;;
  "document get") cp "$OP_STUB_VAULTS/$vault/${positional[0]}" "$out" ;;
  "document create") [ ! -e "$OP_STUB_VAULTS/$vault/$title" ] && cp "${positional[0]}" "$OP_STUB_VAULTS/$vault/$title" ;;
  "document edit") [ -e "$OP_STUB_VAULTS/$vault/${positional[0]}" ] && cp "${positional[1]}" "$OP_STUB_VAULTS/$vault/${positional[0]}" ;;
  "document delete") rm "$OP_STUB_VAULTS/$vault/${positional[0]}" ;;
  *) echo "op stub: unsupported: $kind $action" >&2; exit 2 ;;
esac
SH
chmod +x "$work/bin/op"
export PATH="$work/bin:$PATH"

ana() { (cd "$work/ana" && just "$@"); }
ben() { (cd "$work/ben" && just "$@"); }
check() {
  local description=$1
  shift
  if "$@" >"$work/output" 2>&1; then echo "ok   $description"; else
    echo "FAIL $description"
    cat "$work/output"
    exit 1
  fi
}
refuses() {
  local description=$1
  shift
  if "$@" >"$work/output" 2>&1; then
    echo "FAIL $description"
    cat "$work/output"
    exit 1
  fi
  echo "ok   $description"
}
# Looks at what the previous check or refusal printed.
said() {
  local description=$1 pattern
  shift
  for pattern in "$@"; do
    grep -q -- "$pattern" "$work/output" || {
      echo "FAIL $description"
      cat "$work/output"
      exit 1
    }
  done
  echo "ok   $description"
}
vault="$OP_STUB_VAULTS/team"

ana server-create myvps >/dev/null
echo "SERVER_NAME=myvps" >"$work/ana/servers/myvps/server.env"
check "a server without a source file needs no shared copy" ana _server-config myvps
refuses "push needs a source the first time" ana server-push myvps

refuses "a source that is not op://<vault> is rejected" ana server-push myvps https://example.com
check "and is not kept" test ! -e "$work/ana/servers/myvps/source"

check "the first push publishes server.env" ana server-push myvps op://team
check "the document is named after the server" cmp "$work/ana/servers/myvps/server.env" "$vault/myvps server.env"
check "no Caddyfile document without a Caddyfile" test ! -e "$vault/myvps Caddyfile"
check "the check passes when local and shared match" ana _server-config myvps

check "a second checkout is created from the shared copy" ben server-create myvps op://team
check "it receives server.env" cmp "$work/ana/servers/myvps/server.env" "$work/ben/servers/myvps/server.env"

echo "CLOUDFLARE_ONLY=true" >>"$work/ben/servers/myvps/server.env"
refuses "the check stops on an unpublished local change" ben _server-config myvps
said "and names the file and both ways out" \
  "servers/myvps/server.env" "just server-pull myvps" "just server-push myvps"
check "push publishes the change" ben server-push myvps
refuses "the other checkout is now stopped as stale" ana _server-config myvps
check "pull brings it up to date" ana server-pull myvps
check "after the pull the check passes" ana _server-config myvps

mkdir -p "$work/ana/servers/myvps/caddy"
echo "example.com { respond ok }" >"$work/ana/servers/myvps/caddy/Caddyfile"
check "a new Caddyfile is published" ana server-push myvps
check "pull delivers the Caddyfile" bash -c 'cd "$0/ben" && just server-pull myvps && cmp servers/myvps/caddy/Caddyfile "$0/ana/servers/myvps/caddy/Caddyfile"' "$work"
rm "$work/ana/servers/myvps/caddy/Caddyfile"
check "removing the Caddyfile and pushing removes the document" bash -c 'cd "$0/ana" && just server-push myvps && test ! -e "$1/myvps Caddyfile"' "$work" "$vault"
check "pull then removes it from the other checkout" bash -c 'cd "$0/ben" && just server-pull myvps && test ! -e servers/myvps/caddy/Caddyfile' "$work"

export OP_STUB_SIGNED_IN=0
refuses "the check stops when not signed in" ana _server-config myvps
said "and says how to sign in" "op signin"
refuses "creating from a shared copy fails when not signed in" ana server-create other op://team
check "and leaves no half-made folder" test ! -e "$work/ana/servers/other"
export OP_STUB_SIGNED_IN=1

refuses "creating from a vault with no copy of that server fails" ana server-create nothere op://team
check "and leaves no half-made folder either" test ! -e "$work/ana/servers/nothere"

echo "All checks passed."
