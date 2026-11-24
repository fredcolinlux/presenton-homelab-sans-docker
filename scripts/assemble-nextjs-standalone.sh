#!/usr/bin/env bash
# Assemble le serveur Next.js « standalone » comme le fait le Dockerfile Presenton.
# À exécuter après « npm run build » dans servers/nextjs.
set -euo pipefail

ROOT="${1:-/opt/presenton}"
NEXT_DIR="${ROOT}/servers/nextjs"
STANDALONE="${NEXT_DIR}/.next-build/standalone"
STATIC_SRC="${NEXT_DIR}/.next-build/static"
STATIC_DST="${STANDALONE}/.next-build/static"
PUBLIC_SRC="${NEXT_DIR}/public"
PUBLIC_DST="${STANDALONE}/public"

if [[ ! -f "${STANDALONE}/server.js" ]]; then
  echo "Erreur : ${STANDALONE}/server.js introuvable. Lancer d'abord : cd ${NEXT_DIR} && npm run build" >&2
  exit 1
fi

mkdir -p "${STANDALONE}/.next-build"
if [[ -d "${STATIC_SRC}" ]]; then
  rm -rf "${STATIC_DST}"
  cp -a "${STATIC_SRC}" "${STATIC_DST}"
else
  echo "Erreur : ${STATIC_SRC} introuvable." >&2
  exit 1
fi

if [[ ! -d "${PUBLIC_DST}" && -d "${PUBLIC_SRC}" ]]; then
  cp -a "${PUBLIC_SRC}" "${PUBLIC_DST}"
fi

if [[ ! -f "${STANDALONE}/server.js" || ! -d "${STATIC_DST}" ]]; then
  echo "Assemblage standalone incomplet." >&2
  exit 1
fi

echo "Standalone prêt : ${STANDALONE}/server.js"
echo "Lancement typique :"
echo "  cd ${STANDALONE} && HOSTNAME=127.0.0.1 PORT=3000 node server.js"
