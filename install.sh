#!/usr/bin/env bash
# Installation native de Presenton sur Debian 13 (Trixie), sans Docker.
# À exécuter en root. Relisible et en grande partie idempotent.
#
# Usage :
#   sudo ./install.sh
#   sudo PRESENTON_REPO_URL=https://github.com/presenton/presenton.git ./install.sh
#
# Ce script installe les paquets, clone/construit l'application, pose la
# configuration et les unités systemd. Il n'active pas le service tout seul :
# relisez /etc/presenton/presenton.env puis suivez les instructions affichées.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "À lancer en root (sudo)." >&2
  exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "13" ]]; then
  echo "Attention : ce script cible Debian 13 (Trixie). Système détecté : ${PRETTY_NAME:-inconnu}." >&2
  echo "Poursuite malgré tout dans 5 secondes (Ctrl+C pour annuler)..." >&2
  sleep 5
fi

PRESENTON_ROOT="${PRESENTON_ROOT:-/opt/presenton}"
PRESENTON_DATA="${PRESENTON_DATA:-/var/lib/presenton}"
PRESENTON_CACHE="${PRESENTON_CACHE:-/var/cache/presenton}"
PRESENTON_ENV_DIR="${PRESENTON_ENV_DIR:-/etc/presenton}"
PRESENTON_USER="${PRESENTON_USER:-presenton}"
PRESENTON_REPO_URL="${PRESENTON_REPO_URL:-https://github.com/presenton/presenton.git}"
# Commit / branche / tag à extraire. Vide = branche par défaut (main).
PRESENTON_REF="${PRESENTON_REF:-}"
NODE_MAJOR_REQUIRED=22
NPM_PIN="${NPM_PIN:-11.16.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DEBIAN_FRONTEND=noninteractive

echo "==> Paquets système Debian 13"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg \
  build-essential \
  nginx fontconfig imagemagick zstd \
  fonts-liberation \
  fonts-noto-core fonts-noto-extra fonts-noto-mono \
  fonts-noto-ui-core fonts-noto-ui-extra \
  fonts-noto-cjk fonts-noto-cjk-extra fonts-noto-color-emoji \
  tesseract-ocr tesseract-ocr-eng tesseract-ocr-fra \
  chromium chromium-common chromium-driver \
  xdg-utils

echo "==> Node.js ${NODE_MAJOR_REQUIRED} (NodeSource ; le paquet Debian 13 fournit Node 20, insuffisant pour le frontend officiel)"
need_node=1
if command -v node >/dev/null 2>&1; then
  current_major="$(node -p 'process.versions.node.split(".")[0]')"
  if [[ "${current_major}" -ge "${NODE_MAJOR_REQUIRED}" ]]; then
    echo "    Node $(node -v) déjà présent."
    need_node=0
  fi
fi
if [[ "${need_node}" -eq 1 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y --no-install-recommends nodejs
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "npm introuvable après l'installation de Node." >&2
  exit 1
fi
# Le Dockerfile et la CI Next.js épinglent npm@11.16.0 (overrides du lockfile).
npm install --global "npm@${NPM_PIN}"

echo "==> uv (gestionnaire Python) — le Python système Debian 13 est 3.13, Presenton exige 3.11"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
fi
# Certaines installations placent le binaire dans /root/.local/bin
if ! command -v uv >/dev/null 2>&1 && [[ -x /root/.local/bin/uv ]]; then
  ln -sf /root/.local/bin/uv /usr/local/bin/uv
fi
command -v uv >/dev/null 2>&1 || { echo "uv introuvable." >&2; exit 1; }

echo "==> Utilisateur système ${PRESENTON_USER}"
if ! id "${PRESENTON_USER}" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "${PRESENTON_DATA}" \
    --shell /usr/sbin/nologin "${PRESENTON_USER}"
fi

echo "==> Répertoires"
mkdir -p \
  "${PRESENTON_ROOT}" \
  "${PRESENTON_DATA}/app_data/"{exports,images,uploads,fonts,templates,pptx-to-html,pptx-to-json,mem0} \
  "${PRESENTON_DATA}/tmp" \
  "${PRESENTON_CACHE}/"{huggingface,fastembed,fastembed-icons} \
  "${PRESENTON_ENV_DIR}"

echo "==> Code source"
if [[ ! -d "${PRESENTON_ROOT}/.git" ]]; then
  if [[ -n "${PRESENTON_REF}" ]]; then
    git clone --depth 1 --branch "${PRESENTON_REF}" "${PRESENTON_REPO_URL}" "${PRESENTON_ROOT}"
  else
    git clone --depth 1 "${PRESENTON_REPO_URL}" "${PRESENTON_ROOT}"
  fi
else
  echo "    Dépôt déjà présent dans ${PRESENTON_ROOT} (pas de git pull automatique)."
fi

chown -R "${PRESENTON_USER}:${PRESENTON_USER}" \
  "${PRESENTON_ROOT}" "${PRESENTON_DATA}" "${PRESENTON_CACHE}"

echo "==> Backend Python 3.11 (uv sync --frozen)"
sudo -u "${PRESENTON_USER}" -H bash -c "
  set -euo pipefail
  cd '${PRESENTON_ROOT}/servers/fastapi'
  uv python install 3.11
  uv sync --frozen --no-dev
  uv pip install 'https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl'
  export HF_HOME='${PRESENTON_CACHE}/huggingface'
  export FASTEMBED_CACHE_PATH='${PRESENTON_CACHE}/fastembed'
  export PRESENTON_FASTEMBED_ICON_CACHE_DIR='${PRESENTON_CACHE}/fastembed-icons'
  .venv/bin/python scripts/warm_fastembed_cache.py
"

echo "==> Dépendances Node (racine : LiteParse + runtime d'export) et frontend Next.js"
sudo -u "${PRESENTON_USER}" -H bash -c "
  set -euo pipefail
  cd '${PRESENTON_ROOT}'
  npm ci
  node scripts/sync-document-dependencies.cjs
  node scripts/sync-presentation-export.cjs --force
  node scripts/sync-presentation-export.cjs --check-only
  cd '${PRESENTON_ROOT}/servers/nextjs'
  npm ci
  npm run build
"

echo "==> Assemblage du serveur Next.js standalone"
sudo -u "${PRESENTON_USER}" -H bash "${SCRIPT_DIR}/scripts/assemble-nextjs-standalone.sh" "${PRESENTON_ROOT}"

echo "==> Fichier d'environnement"
if [[ ! -f "${PRESENTON_ENV_DIR}/presenton.env" ]]; then
  cp "${SCRIPT_DIR}/presenton.env.example" "${PRESENTON_ENV_DIR}/presenton.env"
  echo "    Créé ${PRESENTON_ENV_DIR}/presenton.env (à relire et compléter)."
else
  echo "    ${PRESENTON_ENV_DIR}/presenton.env existe déjà, non écrasé."
fi
chown root:"${PRESENTON_USER}" "${PRESENTON_ENV_DIR}/presenton.env"
chmod 0640 "${PRESENTON_ENV_DIR}/presenton.env"

echo "==> Script de lancement FastAPI (charge le workflow ComfyUI s'il est present)"
install -d -m 0755 /opt/presenton/scripts
install -m 0755 "${SCRIPT_DIR}/scripts/presenton-fastapi-start.sh" /opt/presenton/scripts/presenton-fastapi-start.sh
chown "${PRESENTON_USER}:${PRESENTON_USER}" /opt/presenton/scripts/presenton-fastapi-start.sh

echo "==> Unités systemd"
install -m 0644 "${SCRIPT_DIR}/systemd/presenton-fastapi.service" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/systemd/presenton-mcp.service" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/systemd/presenton-nextjs.service" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/systemd/presenton.target" /etc/systemd/system/
# Ajuster ExecStart de Node s'il n'est pas dans /usr/bin/node
NODE_BIN="$(command -v node)"
if [[ "${NODE_BIN}" != "/usr/bin/node" ]]; then
  sed -i "s|^ExecStart=/usr/bin/node |ExecStart=${NODE_BIN} |" /etc/systemd/system/presenton-nextjs.service
fi
systemctl daemon-reload

echo "==> nginx (site Presenton)"
install -m 0644 "${SCRIPT_DIR}/nginx/presenton-maps.conf" /etc/nginx/conf.d/presenton-maps.conf
install -m 0644 "${SCRIPT_DIR}/nginx/presenton.conf" /etc/nginx/sites-available/presenton
ln -sfn /etc/nginx/sites-available/presenton /etc/nginx/sites-enabled/presenton
# Ne pas supprimer automatiquement le site default : l'admin décide.

echo "==> Workflow ComfyUI et site nginx (non activé tant que les IP ne sont pas remplies)"
if [[ ! -f "${PRESENTON_ENV_DIR}/comfyui-workflow.json" ]]; then
  install -m 0644 -o root -g "${PRESENTON_USER}" \
    "${SCRIPT_DIR}/comfyui/sdxl-turbo-api-workflow.json" \
    "${PRESENTON_ENV_DIR}/comfyui-workflow.json"
  echo "    Créé ${PRESENTON_ENV_DIR}/comfyui-workflow.json"
else
  echo "    ${PRESENTON_ENV_DIR}/comfyui-workflow.json existe déjà, non écrasé."
fi
install -m 0644 "${SCRIPT_DIR}/comfyui/nginx-comfyui-upstream.conf" /etc/nginx/sites-available/comfyui-presenton
# Ne pas activer le site : il contient encore les placeholders IP_5070TI / IP_3070TI.

if ! nginx -t; then
  echo "nginx -t a échoué. Vérifiez qu'aucun autre site n'écoute déjà 5001, et que presenton-maps.conf est bien chargé." >&2
  exit 1
fi

echo
echo "Installation terminée."
echo
echo "Prochaines étapes :"
echo "  1. Éditer ${PRESENTON_ENV_DIR}/presenton.env"
echo "     - PRESENTON_PUBLIC_URL (URL réellement utilisée dans le navigateur)"
echo "     - OLLAMA_URL et MEM0_LLM_BASE_URL (remplacer IP_OLLAMA, port 11434 par défaut)"
echo "     - éventuellement AUTH_USERNAME et AUTH_PASSWORD (sinon configuration via l'UI)"
echo "     (LLM=ollama, OLLAMA_MODEL=qwen3.5:9b et IMAGE_PROVIDER=comfyui sont déjà préremplis)"
echo "  2. Remplacer IP_5070TI et IP_3070TI dans /etc/nginx/sites-available/comfyui-presenton"
echo "     puis : ln -sfn /etc/nginx/sites-available/comfyui-presenton /etc/nginx/sites-enabled/comfyui-presenton"
echo "  3. systemctl enable --now presenton.target"
echo "  4. systemctl reload nginx"
echo "  5. Ouvrir http://<hôte>:5001"
echo
echo "Logs : journalctl -u presenton-fastapi -u presenton-nextjs -u presenton-mcp -f"
