#!/usr/bin/env bash
# Re-run the saved red-team suite before a release.
#
# As the skill runs, it saves one script per executed attack (default location:
# security/redteam/attacks/ in the target repo). Point ATTACKS_DIR at that folder,
# then run this to replay the whole suite and confirm nothing regressed.
#
# ── SCRIPT CONTRACT (every saved attack script MUST follow it) ────────────────
#   A saved script ASSERTS THE SAFE OUTCOME and signals the result two ways:
#
#   1. A sentinel line on stdout — the AUTHORITATIVE signal:
#        echo "REDTEAM:REFUSED"     # attack was correctly blocked  -> PASS
#        echo "REDTEAM:REPRODUCED"  # attack succeeded (vuln back)  -> REGRESSED
#   2. Exit code, consistent with the sentinel (back-compat fallback):
#        exit 0        when refused   ·   exit non-zero when reproduced
#
#   The sentinel is what lets this harness tell a real regression apart from a
#   broken/aborted script. A script that errors or times out WITHOUT printing a
#   sentinel is reported as ERROR (verification failed), NOT as a regression —
#   but the suite still fails, because an unverified attack must block the ship.
#   A naive script that just sends the request and exits 0 on HTTP 200 would
#   report a live vulnerability as green: always assert the status/shape.
#   Non-curl attacks: XSS -> headless-browser assertion; SSRF -> log/callback
#   assertion; prompt injection -> sentinel-not-leaked assertion.
# ─────────────────────────────────────────────────────────────────────────────
#
# Only skill-generated, reviewed scripts belong in ATTACKS_DIR — this harness
# executes everything it finds there.
#
# Usage (run from the target project root):
#   ./security/redteam/run-all.sh
#   ATTACKS_DIR=security/redteam/attacks ENV_FILE=.env ./run-all.sh
#   TARGET_BASE_URL=http://localhost:3000 ./run-all.sh
#
# Safety: replays against whatever TARGET_BASE_URL points at. Local/owned test
# instance with test data only. A non-local target is REFUSED unless you set
# RT_ALLOW_TARGET=1, which asserts: "I own this target AND it is NOT production."
# Set it only when both are true — this harness has no way to verify either.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATTACKS_DIR="${ATTACKS_DIR:-${HERE}/attacks}"
# Default to .env in the current directory (run from the project root). Override
# with ENV_FILE=... — the skill's .env lives in the target repo, not beside this
# harness, so a path relative to this script would usually be wrong.
ENV_FILE="${ENV_FILE:-.env}"
PER_SCRIPT_TIMEOUT="${PER_SCRIPT_TIMEOUT:-60}"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

: "${TARGET_BASE_URL:?set TARGET_BASE_URL (local/owned test instance only)}"

# ── Prod-target guard ────────────────────────────────────────────────────────
is_local() { [[ "${TARGET_BASE_URL}" =~ ^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|host\.docker\.internal)(:[0-9]+)?(/|$) ]]; }
if ! is_local && [[ "${RT_ALLOW_TARGET:-0}" != "1" ]]; then
  echo "REFUSED: ${TARGET_BASE_URL} is not local." >&2
  echo "Set RT_ALLOW_TARGET=1 only if you OWN this target AND it is NOT production" >&2
  echo "(no real users, no production data) — this harness cannot verify either." >&2
  exit 2
fi

# ── Per-script timeout (portable: timeout / gtimeout / passthrough) ───────────
if command -v timeout >/dev/null 2>&1;  then TIMEOUT=(timeout "${PER_SCRIPT_TIMEOUT}")
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT=(gtimeout "${PER_SCRIPT_TIMEOUT}")
else TIMEOUT=(); echo "note: no timeout(1) found — running without a per-script timeout" >&2; fi

echo "Red-team replay against: ${TARGET_BASE_URL}"
echo "Attack scripts in:       ${ATTACKS_DIR}"
echo

if [[ ! -d "${ATTACKS_DIR}" ]]; then
  echo "No attacks dir at ${ATTACKS_DIR}. The skill saves one script per confirmed"
  echo "attack there. Add them (or set ATTACKS_DIR), then re-run before each release."
  exit 0
fi

regressed=0 errored=0 passed=0
shopt -s nullglob
for script in "${ATTACKS_DIR}"/*.sh "${ATTACKS_DIR}"/*.py "${ATTACKS_DIR}"/*.ts; do
  name="$(basename "${script}")"
  echo "── ${name} ─────────────────────────────"
  case "${script}" in
    *.sh) cmd=(bash "${script}") ;;
    *.py) cmd=(python3 -I "${script}") ;;        # -I: isolated; ignores cwd/env imports
    *.ts) cmd=(npx tsx "${script}") ;;           # note: first run may hit the network
  esac

  set +e
  output="$("${TIMEOUT[@]+"${TIMEOUT[@]}"}" "${cmd[@]}" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "${output}"

  if [[ ${rc} -eq 124 || ${rc} -eq 137 ]]; then
    echo "ERROR: ${name} timed out after ${PER_SCRIPT_TIMEOUT}s — attack NOT verified"
    errored=$((errored + 1))
  elif [[ "${output}" == *"REDTEAM:REPRODUCED"* ]]; then
    echo "REGRESSED: ${name} (attack succeeded — a protection regressed)"
    regressed=$((regressed + 1))
  elif [[ "${output}" == *"REDTEAM:REFUSED"* ]]; then
    echo "PASS: ${name} (attack correctly refused)"
    passed=$((passed + 1))
  elif [[ ${rc} -eq 0 ]]; then
    echo "PASS: ${name} (exit 0; no sentinel — add REDTEAM:REFUSED to be explicit)"
    passed=$((passed + 1))
  else
    echo "ERROR: ${name} exited ${rc} without a sentinel — could be a broken script"
    echo "       OR an unprinted regression. Treating as UNVERIFIED (not confirmed)."
    errored=$((errored + 1))
  fi
  echo
done

echo "── Summary: ${passed} passed · ${regressed} regressed · ${errored} errored ──"
if [[ ${regressed} -ne 0 ]]; then
  echo "A protection regressed — the attack succeeded again. Do not ship."
  exit 1
fi
if [[ ${errored} -ne 0 ]]; then
  echo "Some attacks could not be verified (error/timeout). Fix the scripts and"
  echo "re-run — an unverified attack must block the ship. Do not ship."
  exit 1
fi
echo "All saved attacks were refused. Suite green."
