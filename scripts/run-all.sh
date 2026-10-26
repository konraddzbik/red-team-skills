#!/usr/bin/env bash
# Re-run the saved red-team suite before a release.
#
# As the skill runs, it saves one script per executed attack (default location:
# security/redteam/attacks/ in the target repo). Point ATTACKS_DIR at that folder,
# then run this to replay the whole suite and confirm nothing regressed.
#
# ── EXIT-CODE CONTRACT (every saved attack script MUST follow it) ─────────────
#   A saved script ASSERTS THE SAFE OUTCOME:
#     exit 0        when the attack is correctly REFUSED  (403 / scoped-empty /
#                   escaped / quota-blocked)              -> PASS
#     exit non-zero when the attack SUCCEEDS              -> REGRESSED (vuln back)
#   A naive script that just sends the request and exits 0 on HTTP 200 reports a
#   LIVE vulnerability as green. Always assert the status/shape, don't just call.
#   Non-curl attacks: XSS -> headless-browser assertion; SSRF -> log/callback
#   assertion; prompt injection -> sentinel-not-leaked assertion.
# ─────────────────────────────────────────────────────────────────────────────
#
# Only skill-generated, reviewed scripts belong in ATTACKS_DIR — this harness
# executes everything it finds there.
#
# Usage:  ATTACKS_DIR=security/redteam/attacks ./run-all.sh
#         TARGET_BASE_URL=http://localhost:3000 ./run-all.sh
#
# Safety: replays against whatever TARGET_BASE_URL points at. Local/owned test
# instance with test data only — never production, never real users. A non-local
# target is refused unless you set RT_ALLOW_TARGET=1 to confirm you own it.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATTACKS_DIR="${ATTACKS_DIR:-${HERE}/attacks}"
ENV_FILE="${ENV_FILE:-${HERE}/../.env}"
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
  echo "REFUSED: ${TARGET_BASE_URL} is not local. Attack only targets you own." >&2
  echo "If you own it and it is NOT production, re-run with RT_ALLOW_TARGET=1." >&2
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

fail=0
shopt -s nullglob
for script in "${ATTACKS_DIR}"/*.sh "${ATTACKS_DIR}"/*.py "${ATTACKS_DIR}"/*.ts; do
  name="$(basename "${script}")"
  echo "── ${name} ─────────────────────────────"
  case "${script}" in
    *.sh) cmd=(bash "${script}") ;;
    *.py) cmd=(python3 -I "${script}") ;;        # -I: isolated; ignores cwd/env imports
    *.ts) cmd=(npx tsx "${script}") ;;           # note: first run may hit the network
  esac
  if "${TIMEOUT[@]}" "${cmd[@]}"; then
    echo "PASS: ${name} (attack correctly refused)"
  else
    echo "REGRESSED: ${name} (attack succeeded — protection failed, or script errored)"
    fail=1
  fi
  echo
done

if [[ "${fail}" -ne 0 ]]; then
  echo "One or more attacks succeeded again — a protection regressed. Do not ship."
  exit 1
fi
echo "All saved attacks were refused. Suite green."
