#!/usr/bin/env bash
# Lance le backend FastAPI en chargeant éventuellement le workflow ComfyUI
# depuis un fichier JSON (COMFYUI_WORKFLOW est une chaîne JSON, pas un chemin).
set -euo pipefail
WORKFLOW_FILE="${COMFYUI_WORKFLOW_FILE:-/etc/presenton/comfyui-workflow.json}"
if [[ -f "${WORKFLOW_FILE}" ]]; then
  # Une seule ligne, tel que json.loads() l'attend dans Presenton.
  export COMFYUI_WORKFLOW="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))' "${WORKFLOW_FILE}")"
fi
exec /opt/presenton/servers/fastapi/.venv/bin/python server.py --port 8000 --reload false
