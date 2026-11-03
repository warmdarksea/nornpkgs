#!/usr/bin/env bash
# The nixpkgs revision for `make bump`: the newest nixos-unstable channel
# revision of the last NIX_BUMP_DAYS days (default 7) at which every expensive
# package of lib/bigpkgs.nix is in cache.nixos.org or cache.nixos-cuda.org, so
# the bump stays a download instead of an hours-long build (vector and its rust
# toolchain, lean4, the CUDA group). The candidates are hydra's evaluations of
# the nixos:unstable jobset whose `tested` job passed, which is exactly the set
# of revisions the channel has pointed at.
#
#   bin/nixpkgs_maximize_cache.sh        the revision on stdout, the table of
#                                        candidates and their misses on stderr;
#                                        exit 1 when none of the window is good
#   bin/nixpkgs_maximize_cache.sh --all  score every candidate instead of
#                                        stopping at the first good one
#   NIX_BUMP_DAYS=14 bin/nixpkgs_maximize_cache.sh
#
# Needs nix, curl, jq.
set -euo pipefail

all=
case ${1:-} in
  '') ;;
  --all) all=1 ;;
  -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "nixpkgs_maximize_cache: unknown argument $1" >&2; exit 2 ;;
esac

days=${NIX_BUMP_DAYS:-7}
here=$(cd "$(dirname "$0")/.." && pwd)
hydra=https://hydra.nixos.org
caches="https://cache.nixos.org https://cache.nixos-cuda.org"
cutoff=$(( $(date +%s) - days * 86400 ))

log() { printf '%s\n' "$*" >&2; }
get() { curl -sSfL --retry 3 -H 'Accept: application/json' "$@"; }

# "rev timestamp" of every nixos:unstable evaluation newer than the cutoff
# whose tested job finished successfully, newest first
candidates() {
  local page=1 oldest evals
  while :; do
    evals=$(get "$hydra/jobset/nixos/unstable/evals?page=$page")
    jq -r '.evals[] | "\(.id) \(.jobsetevalinputs.nixpkgs.revision) \(.timestamp)"' <<<"$evals" \
    | while read -r id rev ts; do
        [ "$ts" -ge "$cutoff" ] || continue
        # the channel's own criterion: tested finished and succeeded
        if [ "$(get "$hydra/eval/$id/job/tested" 2>/dev/null | jq -r '"\(.finished)\(.buildstatus)"')" = 10 ]; then
          echo "$rev $ts"
        fi
      done
    oldest=$(jq -r '.evals | map(.timestamp) | min' <<<"$evals")
    [ "$oldest" -ge "$cutoff" ] || break
    page=$((page + 1))
  done
}

# the packages of lib/bigpkgs.nix that are in neither cache at $1
misses() {
  local rev=$1 tracers
  if ! tracers=$(nix eval --impure --json --expr "import $here/lib/bigpkgs.nix { rev = \"$rev\"; }" 2>/dev/null); then
    echo "(evaluation failed)"
    return
  fi
  # one line per package: name hash; one that does not evaluate at this
  # revision (null path) is reported as name!eval
  jq -r '.[] | if .path == null then "\(.name)!eval -" else "\(.name) \(.path[11:43])" end' <<<"$tracers" \
  | xargs -P 16 -L 1 sh -c '
      name=$1; hash=$2
      for cache in '"$caches"'; do
        [ "$hash" = - ] && break
        [ "$(curl -s -o /dev/null -w "%{http_code}" -I "$cache/$hash.narinfo")" = 200 ] && exit 0
      done
      echo "$name"' sh \
  | sort | tr '\n' ' '
}

found=
while read -r rev ts; do
  [ -n "$rev" ] || continue
  m=$(misses "$rev")
  log "$(printf '%-12s %-10s %s' "${rev:0:11}" "$(date -u -d @"$ts" +%F)" "misses: ${m:-none}")"
  if [ -z "$m" ] && [ -z "$found" ]; then
    found=$rev
    [ -n "$all" ] || break
  fi
done < <(candidates)

if [ -z "$found" ]; then
  log "nixpkgs_maximize_cache: no channel revision of the last $days days has every package of lib/bigpkgs.nix cached"
  exit 1
fi
echo "$found"
