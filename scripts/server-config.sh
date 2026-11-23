#!/usr/bin/env bash
# Keeps a server folder in step with the shared copy its `source` file points at
# (docs/architecture.md, "Shared server config").
#
#   server-config.sh check <name>   stop when the local files differ from the shared ones
#   server-config.sh pull <name>    replace the local files with the shared ones
#   server-config.sh push <name> [op://<vault>]   publish the local files as the shared ones;
#                                                 the vault is given the first time
set -euo pipefail

command=$1
name=$2
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/servers/$name"
FILES=(server.env caddy/Caddyfile)

fail() {
  echo "$*" >&2
  exit 1
}

new_source=${3:-}
if [ -n "$new_source" ]; then
  source=$new_source
elif [ -f "$dir/source" ]; then
  source=$(<"$dir/source")
elif [ "$command" = check ]; then
  exit 0
else
  fail "servers/$name has no source file, so it has no shared copy"
fi
[[ "$source" =~ ^op://[^/]+$ ]] || fail "The source of servers/$name must be op://<vault> (got '$source')"
vault=${source#op://}

shared=$(mktemp -d)
trap 'rm -rf "$shared"' EXIT

title() { echo "$name ${1##*/}"; }

# A missing document is not an error (the Caddyfile is optional), so access is checked first:
# after it, a failed download means the document does not exist.
fetch_shared() {
  local file
  op vault get "$vault" >/dev/null 2>&1 ||
    fail "Cannot read the 1Password vault '$vault'. Sign in first: eval \$(op signin)"
  for file in "${FILES[@]}"; do
    mkdir -p "$(dirname "$shared/$file")"
    op document get "$(title "$file")" --vault "$vault" --out-file "$shared/$file" --force \
      >/dev/null 2>&1 || rm -f "$shared/$file"
  done
}

same() { cmp -s <(cat "$dir/$1" 2>/dev/null) <(cat "$shared/$1" 2>/dev/null); }

check() {
  local file differing=()
  for file in "${FILES[@]}"; do
    same "$file" || differing+=("servers/$name/$file")
  done
  [ ${#differing[@]} -gt 0 ] || return 0
  {
    echo "These files differ from the shared copy in the 1Password vault '$vault':"
    printf '  %s\n' "${differing[@]}"
    echo "Take the shared copy (overwrites yours):  just server-pull $name"
    echo "Publish yours as the shared copy:         just server-push $name"
  } >&2
  exit 1
}

pull() {
  local file
  [ -f "$shared/server.env" ] ||
    fail "The vault '$vault' has no '$(title server.env)' document. Publish one: just server-push $name"
  for file in "${FILES[@]}"; do
    same "$file" && continue
    if [ -f "$shared/$file" ]; then
      mkdir -p "$(dirname "$dir/$file")"
      install -m 600 "$shared/$file" "$dir/$file"
      echo "Updated servers/$name/$file"
    else
      rm -f "$dir/$file"
      echo "Removed servers/$name/$file (it has no shared copy)"
    fi
  done
}

push() {
  local file
  [ -f "$dir/server.env" ] || fail "servers/$name/server.env does not exist"
  [ -z "$new_source" ] || echo "$new_source" >"$dir/source"
  for file in "${FILES[@]}"; do
    same "$file" && continue
    if [ ! -s "$dir/$file" ]; then
      op document delete "$(title "$file")" --vault "$vault" >/dev/null
      echo "Removed '$(title "$file")' from the vault '$vault'"
    elif [ -f "$shared/$file" ]; then
      op document edit "$(title "$file")" "$dir/$file" --vault "$vault" >/dev/null
      echo "Updated '$(title "$file")' in the vault '$vault'"
    else
      op document create "$dir/$file" --vault "$vault" --title "$(title "$file")" >/dev/null
      echo "Created '$(title "$file")' in the vault '$vault'"
    fi
  done
}

case "$command" in
  check | pull | push)
    fetch_shared
    "$command"
    ;;
  *) fail "usage: server-config.sh check|pull|push <name> [op://<vault>]" ;;
esac
