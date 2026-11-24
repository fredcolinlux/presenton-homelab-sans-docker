#!/usr/bin/env bash
# Tests depuis la machine Presenton. Remplacez IP_5070TI et IP_3070TI.
set -euo pipefail
PRIMARY="${IP_5070TI:-IP_5070TI}"
BACKUP="${IP_3070TI:-IP_3070TI}"
PROXY="${COMFYUI_URL:-http://127.0.0.1:8188}"
WORKFLOW="${1:-/etc/presenton/comfyui-workflow.json}"

check() {
  local name="$1" url="$2"
  echo "======= $name  $url/system_stats ======="
  if curl -sS -m 5 -o /tmp/comfy-stats.json -w "http:%{http_code}\n" "${url}/system_stats"; then
    python3 -c "import json; d=json.load(open('/tmp/comfy-stats.json')); print(d.get('devices') or d.get('system') or d)" 2>/dev/null || head -c 300 /tmp/comfy-stats.json; echo
  else
    echo "INJOIGNABLE"
  fi
}

if [[ "${PRIMARY}" == "IP_5070TI" || "${BACKUP}" == "IP_3070TI" ]]; then
  echo "Definissez IP_5070TI et IP_3070TI, par exemple :"
  echo "  IP_5070TI=192.168.1.10 IP_3070TI=192.168.1.11 $0"
  echo
fi

check "5070 Ti (primaire)" "http://${PRIMARY}:8188"
check "3070 Ti (secours)"  "http://${BACKUP}:8188"
check "proxy local nginx"  "${PROXY}"

if [[ -f "${WORKFLOW}" ]]; then
  echo "======= POST ${PROXY}/prompt (workflow) ======="
  python3 - "${WORKFLOW}" "${PROXY}" << 'PY'
import json, sys, urllib.request
workflow = json.load(open(sys.argv[1]))
payload = json.dumps({"prompt": workflow, "client_id": "presenton-test"}).encode()
req = urllib.request.Request(sys.argv[2].rstrip("/") + "/prompt", data=payload, headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)
    print(json.dumps(data, indent=2)[:1000])
    pid = data.get("prompt_id")
    if pid:
        print("Suivi : curl -sS %s/history/%s" % (sys.argv[2].rstrip("/"), pid))
except Exception as exc:
    print("Echec:", exc)
    sys.exit(1)
PY
else
  echo "Pas de workflow en ${WORKFLOW} ; installez-le avec install-workflow-on-presenton.sh"
fi
