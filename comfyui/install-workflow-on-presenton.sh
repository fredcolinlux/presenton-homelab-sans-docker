#!/usr/bin/env bash
# Copie le workflow API sur la machine Presenton.
# Usage : sudo ./install-workflow-on-presenton.sh
set -euo pipefail
if [[ "${EUID}" -ne 0 ]]; then
  echo "A lancer en root (sudo)." >&2
  exit 1
fi
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sdxl-turbo-api-workflow.json"
install -d -m 0755 /etc/presenton
install -m 0644 -o root -g presenton "${SRC}" /etc/presenton/comfyui-workflow.json
python3 -c "import json; json.load(open('/etc/presenton/comfyui-workflow.json')); print('Workflow JSON valide : /etc/presenton/comfyui-workflow.json')"
echo "Redemarrez le backend : sudo systemctl restart presenton-fastapi"
