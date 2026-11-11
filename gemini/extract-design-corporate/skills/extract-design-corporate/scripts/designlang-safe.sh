#!/usr/bin/env bash
# designlang-safe.sh — policy-enforcing wrapper around the designlang CLI.
#
# Usage: designlang-safe.sh [subcommand] <url…> [flags…]
#
# Environment (set by your IT/platform team, ideally in managed settings):
#   DESIGNLANG_BIN             Absolute path to a vetted, pre-installed designlang binary.
#                              If unset, falls back to `npx designlang@$DESIGNLANG_VERSION`.
#   DESIGNLANG_VERSION         Pinned version for the npx fallback (default below).
#   DESIGNLANG_ALLOWED_HOSTS   Comma-separated host suffixes the tool may visit,
#                              e.g. "example.com,intranet.example.corp". Unset = any public host.
#   DESIGNLANG_ALLOW_INTERNAL  =1 to permit private/loopback addresses (RFC1918, localhost).
#   DESIGNLANG_ALLOW_SMART     =1 to permit --smart (sends page text to a 3rd-party LLM API).
#   DESIGNLANG_ALLOW_INSECURE  =1 to permit --insecure (disables TLS verification).
#   DESIGNLANG_SYSTEM_CHROME   =1 to add --system-chrome (use the managed Chrome install,
#                              skipping the Playwright Chromium download).
#   DESIGNLANG_AUDIT_LOG       File to append one line per run (time, user, command, host).
set -euo pipefail

DESIGNLANG_VERSION="${DESIGNLANG_VERSION:-13.4.0}"

die() { echo "designlang-safe: $*" >&2; exit 2; }

[ "$#" -ge 1 ] || die "usage: designlang-safe.sh [subcommand] <url…> [flags…]"

# --- 1. Subcommand policy -------------------------------------------------
# Blocked: network listeners and long-running/agentic modes.
#   studio  -> starts an HTTP server (binds all interfaces by default)
#   mcp     -> starts a long-lived stdio server
#   watch   -> unattended recurring requests
#   chat    -> interactive REPL, may call an LLM
SUBCOMMANDS=" diff history brands sync clone site watch score slop verify-ui stats grade battle remix pack theme-swap brand pair apply export lint drift visual-diff verify fidelity studio mcp chat install-browser doctor "
sub=""
if [[ "$SUBCOMMANDS" == *" $1 "* ]]; then sub="$1"; fi
case "$sub" in
  studio|mcp|watch|chat)
    die "'$sub' is disabled by corporate policy (opens a listener or runs unattended)." ;;
esac

# --- 2. Flag policy -------------------------------------------------------
for a in "$@"; do
  case "$a" in
    --smart)
      [ "${DESIGNLANG_ALLOW_SMART:-0}" = 1 ] || die "--smart sends page content to an external LLM API; requires DESIGNLANG_ALLOW_SMART=1 (security approval)." ;;
    --insecure)
      [ "${DESIGNLANG_ALLOW_INSECURE:-0}" = 1 ] || die "--insecure disables TLS verification; install the corporate root CA instead (see references/corporate-setup.md)." ;;
    --cookie|--cookie=*|--header|--header=*)
      die "inline credentials are visible in process lists and shell history; use --cookie-file <path> (mode 600) instead." ;;
  esac
done

# --- 3. URL policy --------------------------------------------------------
urls=()
for a in "$@"; do
  case "$a" in http://*|https://*) urls+=("$a") ;; esac
done
[ "${#urls[@]}" -ge 1 ] || [ "$sub" = "lint" ] || [ "$sub" = "install-browser" ] || [ "$sub" = "doctor" ] \
  || [ "$sub" = "visual-diff" ] || die "no http(s) URL found in arguments."

check_host() {
  local url="$1" host
  host="${url#*://}"; host="${host%%/*}"; host="${host##*@}"; host="${host%%:*}"
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  [ -n "$host" ] || die "could not parse host from: $url"

  # Always blocked: link-local / cloud metadata endpoints.
  case "$host" in
    169.254.*|metadata.google.internal|metadata|instance-data|fd00:ec2::254|*.internal.cloud.invalid)
      die "blocked host (cloud metadata / link-local): $host" ;;
  esac
  # Private ranges need explicit opt-in.
  if [ "${DESIGNLANG_ALLOW_INTERNAL:-0}" != 1 ]; then
    case "$host" in
      localhost|127.*|0.0.0.0|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|*.local|\[::1\]|::1)
        die "private/loopback host '$host' requires DESIGNLANG_ALLOW_INTERNAL=1." ;;
    esac
  fi
  # Optional allow-list.
  if [ -n "${DESIGNLANG_ALLOWED_HOSTS:-}" ]; then
    local ok=0 suf
    IFS=',' read -ra sufs <<<"$DESIGNLANG_ALLOWED_HOSTS"
    for suf in "${sufs[@]}"; do
      suf="$(printf '%s' "$suf" | tr -d ' ' | tr '[:upper:]' '[:lower:]')"
      [ -n "$suf" ] || continue
      if [ "$host" = "$suf" ] || [[ "$host" == *".$suf" ]]; then ok=1; break; fi
    done
    [ "$ok" = 1 ] || die "host '$host' is not in DESIGNLANG_ALLOWED_HOSTS."
  fi
  printf '%s' "$host"
}

hosts=""
for u in "${urls[@]+"${urls[@]}"}"; do
  h="$(check_host "$u")"
  hosts="${hosts:+$hosts,}$h"
done

# --- 4. Assemble the command ----------------------------------------------
args=("$@")
if [ "${DESIGNLANG_SYSTEM_CHROME:-0}" = 1 ]; then
  case "$sub" in ""|clone|verify|fidelity) args+=("--system-chrome") ;; esac
fi

if [ -n "${DESIGNLANG_BIN:-}" ]; then
  [ -x "$DESIGNLANG_BIN" ] || die "DESIGNLANG_BIN is not executable: $DESIGNLANG_BIN"
  cmd=("$DESIGNLANG_BIN")
else
  command -v npx >/dev/null || die "npx not found and DESIGNLANG_BIN not set."
  # Pinned version, lifecycle scripts disabled, registry comes from the user's/org npm config.
  export npm_config_ignore_scripts=true
  cmd=(npx --yes "designlang@${DESIGNLANG_VERSION}")
fi

# --- 5. Audit + run ---------------------------------------------------------
if [ -n "${DESIGNLANG_AUDIT_LOG:-}" ]; then
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "${USER:-unknown}" "${sub:-extract}" "${hosts:-n/a}" \
    >> "$DESIGNLANG_AUDIT_LOG" 2>/dev/null || echo "designlang-safe: warning: cannot write audit log" >&2
fi

exec "${cmd[@]}" "${args[@]}"
