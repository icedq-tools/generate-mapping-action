#!/usr/bin/env bash
set -euo pipefail

ARGS=(
  "generate-mapping"
  "--bundle" "${BUNDLE}"
  "--output" "${OUTPUT_FILE}"
  "--output-format" "json"
)

# Ensure parent directory for the output file exists.
mkdir -p "$(dirname "${OUTPUT_FILE}")"

TMP_JSON="$(mktemp)"
TMP_ERR="$(mktemp)"
set +e
icedq "${ARGS[@]}" >"${TMP_JSON}" 2>"${TMP_ERR}"
EXIT_CODE=$?
set -e

# Forward CLI stderr (logs) to the action log.
cat "${TMP_ERR}" >&2

if command -v jq >/dev/null 2>&1; then
  MAPPING_FILE="$(jq -r '.outputFile // empty' "${TMP_JSON}" 2>/dev/null || true)"
  CONNECTIONS="$(jq -r '.connections // 0' "${TMP_JSON}" 2>/dev/null || echo 0)"
  PARAMETERS="$(jq -r '.parameters // 0' "${TMP_JSON}" 2>/dev/null || echo 0)"
  CUSTOM_FIELDS="$(jq -r '.customFields // 0' "${TMP_JSON}" 2>/dev/null || echo 0)"
else
  MAPPING_FILE="$(node -e "try{console.log(JSON.parse(require('fs').readFileSync('${TMP_JSON}','utf8')).outputFile||'')}catch(e){}")"
  CONNECTIONS="$(node -e "try{console.log(JSON.parse(require('fs').readFileSync('${TMP_JSON}','utf8')).connections||0)}catch(e){console.log(0)}")"
  PARAMETERS="$(node -e "try{console.log(JSON.parse(require('fs').readFileSync('${TMP_JSON}','utf8')).parameters||0)}catch(e){console.log(0)}")"
  CUSTOM_FIELDS="$(node -e "try{console.log(JSON.parse(require('fs').readFileSync('${TMP_JSON}','utf8')).customFields||0)}catch(e){console.log(0)}")"
fi

# Fall back to the requested OUTPUT_FILE when CLI didn't surface it.
if [[ -z "${MAPPING_FILE}" ]]; then
  MAPPING_FILE="${OUTPUT_FILE}"
fi

{
  echo "mapping-file=${MAPPING_FILE}"
} >>"${GITHUB_OUTPUT}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## iceDQ generate-mapping"
    echo ""
    echo "- **Mapping file:** \`${MAPPING_FILE}\`"
    echo "- **Connections mapped:** ${CONNECTIONS:-0}"
    echo "- **Parameters mapped:** ${PARAMETERS:-0}"
    echo "- **Custom fields mapped:** ${CUSTOM_FIELDS:-0}"
    echo "- **Workspace:** \`${ICEDQ_WORKSPACE_ID}\`"
    echo "- **Bundle:** \`${BUNDLE}\`"
  } >>"${GITHUB_STEP_SUMMARY}"
fi

cat "${TMP_JSON}"

exit "${EXIT_CODE}"
