# Installer Presenton sur un homelab Debian 13, sans Docker

Guide technique détaillé. Si tu débutes, commence par le [tutoriel pas à pas](../README.md).

Guide pour [presenton/presenton](https://github.com/presenton/presenton), générateur de présentations IA open-source, en installation **native** sur **Debian 13 (Trixie)**.

**Licences.** Presenton est un projet **tiers**, publié sous [Apache License 2.0](https://github.com/presenton/presenton/blob/main/LICENSE). Ce dépôt (tutoriel, scripts d’installation, fichiers systemd/nginx/ComfyUI) est sous licence [MIT](../LICENSE).

L’éditeur ne documente officiellement que **Docker** et l’application **Electron**. Cette procédure reproduit les étapes du `Dockerfile` et de `start.js` (Python 3.11, Node 22, runtime d’export, FastAPI, Next.js standalone, nginx) sans conteneur.

**Version examinée :** Presenton `0.9.12-beta`, dépôt cloné le 24 novembre 2026 (commit `ac708ab` sur `main`). Les commandes et versions ci-dessous sont celles du dépôt à cette date.

Fichiers d’accompagnement (unités systemd, nginx, `.env`, script d’install, **ComfyUI**) : à la racine de ce dépôt (`install.sh`, `presenton.env.example`, `nginx/`, `systemd/`, `scripts/`, `comfyui/`). Clonez le dépôt sur le homelab, par exemple dans `/root/presenton-homelab-sans-docker/`.

---

## 1. Architecture

Presenton n’est pas un binaire unique. Quatre processus doivent tourner :

| Processus | Rôle | Écoute |
| --- | --- | --- |
| FastAPI (`server.py`) | API, auth, LLM, base SQLite, templates | `127.0.0.1:8000` |
| MCP (`mcp_server.py`) | Outils MCP (génération via API) | `127.0.0.1:8001` |
| Next.js (standalone `server.js`) | Interface web | `127.0.0.1:3000` |
| nginx (Presenton) | Front public, WebSocket, fichiers `/static` et `/app_data` | `0.0.0.0:5001` (réglable) |
| nginx (proxy ComfyUI) | Basculement 5070 Ti → 3070 Ti (secours) | `127.0.0.1:8188` (local seulement) |

Le navigateur ne doit parler qu’à nginx (port **5001** par défaut, comme le `docker run -p 5001:80` officiel). FastAPI, Next.js et MCP restent en boucle locale.

Chemins recommandés :

| Chemin | Contenu |
| --- | --- |
| `/opt/presenton` | Code source + environnements Python/Node |
| `/var/lib/presenton/app_data` | Données (`APP_DATA_DIRECTORY`) : base SQLite, exports, images, `userConfig.json` |
| `/var/cache/presenton` | Caches Hugging Face / FastEmbed |
| `/etc/presenton/presenton.env` | Variables d’environnement (secrets) |
| `/etc/presenton/comfyui-workflow.json` | Workflow ComfyUI au format API (chargé au démarrage de FastAPI) |
| Utilisateur `presenton` | Compte système qui exécute les services |

**LibreOffice n’est pas requis.** L’export PPTX/PDF passe par Chromium, ImageMagick, `python-pptx` et le paquet `@presenton/export-core` (téléchargé depuis les releases GitHub, version épinglée `v1.0.51` dans le `package.json` racine). L’OCR des documents s’appuie sur **Tesseract** et **LiteParse** (Node).

Ressources : au repos, Presenton est léger. Une génération (surtout avec Ollama ou un export Chromium sur la même machine) demande de la RAM. Visez **4 Go au minimum** pour Presenton seul, **8 Go ou plus** si Ollama tourne sur le même hôte. Un test de charge officiel (4 générations simultanées, sans export PPTX) a vu le tas processus monter vers ~12 Go dans le pire cas.

---

## 2. Prérequis Debian 13

- Debian 13 (Trixie), amd64, accès root (`sudo`).
- Accès Internet pour cloner le dépôt, installer les paquets, `uv`, npm et le runtime d’export.
- Ports libres : **5001** (public), ainsi que 3000, 8000, 8001 et **8188** (proxy ComfyUI, uniquement en `127.0.0.1`) en local. Le flux OAuth « Codex / ChatGPT » utilise aussi le port **1455** (peu pratique si le navigateur n’est pas sur la même machine que Presenton).

**Point important — versions de runtime :**

- Le Python **système** de Debian 13 est **3.13**. Presenton exige **`Python >= 3.11 et < 3.12`** (`servers/fastapi/pyproject.toml` et `.python-version`). Il faut donc installer **Python 3.11 avec [uv](https://docs.astral.sh/uv/)**, pas le `python3` Debian.
- Le paquet Debian `nodejs` est en **20.19.x**. Le `Dockerfile` et la CI du frontend utilisent **Node 22** et épinglent **npm 11.16.0**. Installez Node 22 via **NodeSource** (ou nvm), pas `apt install nodejs`.

### Variantes brèves (autres OS)

- **Ubuntu 24.04 / 26.04 :** mêmes grandes étapes ; les noms de paquets Chromium / polices sont proches. Vérifiez que le paquet `chromium` existe (Ubuntu fournit parfois `chromium-browser`). Python 3.11 via `uv` reste le choix le plus sûr.
- **Fedora / RHEL :** remplacez `apt` par `dnf` (`nginx`, `chromium`, `tesseract`, `ImageMagick`, polices Noto). Node 22 via NodeSource ou Fedora Node, Python 3.11 via `uv`. Les unités systemd et le site nginx restent valables.

---

## 3. Installation rapide (script)

Sur le homelab, après avoir cloné ce dépôt :

```bash
sudo ./install.sh
```

Le script installe les paquets Trixie, Node 22 (NodeSource), `uv`, Python 3.11, clone le dépôt dans `/opt/presenton`, construit le backend et le frontend, pose `/etc/presenton/presenton.env`, les unités systemd et le site nginx. **Il n’active pas les services tout seul** : relisez le `.env`, puis :

```bash
sudo nano /etc/presenton/presenton.env
sudo systemctl enable --now presenton.target
sudo systemctl reload nginx
```

Ouvrez `http://<ip-ou-nom>:5001`.

Les sections suivantes détaillent la même procédure à la main (utile pour comprendre, déboguer ou adapter).

---

## 4. Paquets système

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg build-essential \
  nginx fontconfig imagemagick zstd \
  fonts-liberation \
  fonts-noto-core fonts-noto-extra fonts-noto-mono \
  fonts-noto-ui-core fonts-noto-ui-extra \
  fonts-noto-cjk fonts-noto-cjk-extra fonts-noto-color-emoji \
  tesseract-ocr tesseract-ocr-eng tesseract-ocr-fra \
  chromium chromium-common chromium-driver \
  xdg-utils
```

Versions candidates observées sur Trixie le 24 novembre 2026 :

- nginx `1.26.3-3+deb13u11` (module `http_auth_request_module` inclus, indispensable pour protéger `/app_data`)
- chromium `156.0.8078.79-1~deb13u1` (le Docker officiel épingle une version snapshot plus ancienne ; le Chromium du dépôt Debian suffit)
- tesseract `5.5.0`, ImageMagick `7.1.1.43`, zstd `1.5.7`

`tesseract-ocr-fra` est facultatif mais utile pour des documents en français. Ne **supprimez pas** les polices non-Noto du système (le `Dockerfile` le fait dans l’image, ce n’est pas souhaitable sur un homelab).

Vérifiez le binaire Chromium :

```bash
ls -l /usr/bin/chromium
```

---

## 5. Node.js 22 et npm 11.16.0

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt-get install -y --no-install-recommends nodejs
sudo npm install --global npm@11.16.0
node -v   # v22.x
npm -v    # 11.16.0
```

Alternative : [nvm](https://github.com/nvm-sh/nvm) (`nvm install 22`) pour l’utilisateur `presenton`. Dans ce cas, mettez le chemin exact de `node` dans `ExecStart` de l’unité `presenton-nextjs.service` (pas seulement un `~/.nvm` qui n’est pas chargé par systemd).

---

## 6. Utilisateur, répertoires, code

```bash
sudo useradd --system --create-home --home-dir /var/lib/presenton \
  --shell /usr/sbin/nologin presenton || true

sudo mkdir -p \
  /opt/presenton \
  /var/lib/presenton/app_data/{exports,images,uploads,fonts,templates,pptx-to-html,pptx-to-json,mem0} \
  /var/lib/presenton/tmp \
  /var/cache/presenton/{huggingface,fastembed,fastembed-icons} \
  /etc/presenton

sudo git clone https://github.com/presenton/presenton.git /opt/presenton
# Optionnel : basculer sur un tag si vous voulez figer une release
# cd /opt/presenton && sudo git checkout <tag>

sudo chown -R presenton:presenton /opt/presenton /var/lib/presenton /var/cache/presenton
```

---

## 7. Backend FastAPI (Python 3.11 via uv)

```bash
# uv, une seule fois (binaire dans /usr/local/bin)
curl -LsSf https://astral.sh/uv/install.sh | sudo env UV_INSTALL_DIR=/usr/local/bin sh

sudo -u presenton -H bash -c '
  set -euo pipefail
  cd /opt/presenton/servers/fastapi
  uv python install 3.11
  uv sync --frozen --no-dev
  # Modèle spaCy exigé par Mem0 (comme dans le Dockerfile)
  uv pip install "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"
  export HF_HOME=/var/cache/presenton/huggingface
  export FASTEMBED_CACHE_PATH=/var/cache/presenton/fastembed
  export PRESENTON_FASTEMBED_ICON_CACHE_DIR=/var/cache/presenton/fastembed-icons
  .venv/bin/python scripts/warm_fastembed_cache.py
  .venv/bin/python -V   # doit afficher Python 3.11.x
'
```

`uv sync --frozen` installe les dépendances verrouillées par `uv.lock` (FastAPI, llmai, mem0, fastembed, openai, google-genai, etc.) dans `/opt/presenton/servers/fastapi/.venv`. Le préchauffage FastEmbed télécharge notamment `BAAI/bge-small-en-v1.5` et `Qdrant/bm25`.

Lancement manuel de test :

```bash
sudo -u presenton -H bash -c '
  set -a
  source /etc/presenton/presenton.env
  set +a
  cd /opt/presenton/servers/fastapi
  exec .venv/bin/python server.py --port 8000 --reload false
'
```

Au premier démarrage, Alembic applique les migrations, crée l’administrateur si `AUTH_USERNAME` / `AUTH_PASSWORD` sont définis, et importe les templates par défaut (civic, dynamic, executive, etc.). Vérification :

```bash
curl -sS http://127.0.0.1:8000/api/v1/auth/status
# {"configured":true,"authenticated":false,...}
```

Le serveur MCP :

```bash
cd /opt/presenton/servers/fastapi
.venv/bin/python mcp_server.py --port 8001
# écoute http://127.0.0.1:8001/mcp  (401 sans jeton Bearer : normal)
```

---

## 8. Runtime d’export, LiteParse, frontend Next.js

Toujours en utilisateur `presenton`, depuis la racine du dépôt :

```bash
sudo -u presenton -H bash -c '
  set -euo pipefail
  cd /opt/presenton
  npm ci
  node scripts/sync-document-dependencies.cjs
  node scripts/sync-presentation-export.cjs --force
  node scripts/sync-presentation-export.cjs --check-only

  cd /opt/presenton/servers/nextjs
  npm ci
  npm run build

  # Assemblage identique au Dockerfile :
  # standalone/ devient le runtime, plus les assets statiques
  cp -a .next-build/static .next-build/standalone/.next-build/static
  # public/ est déjà copié dans standalone avec Next 16.4.6 ; sinon :
  # cp -a public .next-build/standalone/public
'
```

Cela installe notamment :

- `@llamaindex/liteparse` dans `document-extraction-liteparse/` (analyse de documents) ;
- `@presenton/export-core` **1.0.51** dans `presentation-export/` (téléchargement depuis `https://github.com/presenton/presenton-export/releases/download/v1.0.51/...`).

Le `next.config.mjs` fixe `output: "standalone"` et `distDir: ".next-build"`. **Utilisez `node …/standalone/server.js`**, pas `next start` (Next 16 affiche : `"next start" does not work with "output: standalone"`). Lors des tests, `next start` a malgré tout servi l’UI, mais le mode standalone est le chemin prévu en production (et celui de l’image Docker).

```bash
cd /opt/presenton/servers/nextjs/.next-build/standalone
HOSTNAME=127.0.0.1 PORT=3000 node server.js
# http://127.0.0.1:3000
```

Un script équivalent se trouve dans `scripts/assemble-nextjs-standalone.sh`.

---

## 9. Fichier d’environnement

```bash
sudo cp presenton.env.example /etc/presenton/presenton.env
sudo chown root:presenton /etc/presenton/presenton.env
sudo chmod 0640 /etc/presenton/presenton.env
sudo nano /etc/presenton/presenton.env
```

Variables **obligatoires** pour un démarrage natif :

```bash
APP_DATA_DIRECTORY=/var/lib/presenton/app_data
TEMP_DIRECTORY=/var/lib/presenton/tmp
USER_CONFIG_PATH=/var/lib/presenton/app_data/userConfig.json
EXPORT_PACKAGE_ROOT=/opt/presenton/presentation-export
PRESENTON_APP_ROOT=/opt/presenton
HF_HOME=/var/cache/presenton/huggingface
FASTEMBED_CACHE_PATH=/var/cache/presenton/fastembed
PRESENTON_FASTEMBED_ICON_CACHE_DIR=/var/cache/presenton/fastembed-icons
PRESENTON_PUBLIC_URL=http://IP_PRESENTON:5001   # l’URL vraiment ouverte dans le navigateur
FAST_API_INTERNAL_URL=http://127.0.0.1:8000
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
MIGRATE_DATABASE_ON_STARTUP=true
START_OLLAMA=false
```

Sans `APP_DATA_DIRECTORY`, l’entrée Docker `start.js` refuse de démarrer. FastAPI se rabat sur `/tmp/presenton` pour la base SQLite si la variable est absente : ce n’est pas souhaitable en service.

`DATABASE_URL` peut rester vide (SQLite dans `APP_DATA_DIRECTORY/fastapi.db`). PostgreSQL et MySQL sont pris en charge (`postgresql://…`, `mysql://…`).

### Authentification

Au premier lancement, soit vous ouvrez l’UI et créez le compte administrateur (nom ≥ 3 caractères, mot de passe ≥ 8), soit vous définissez :

```bash
AUTH_USERNAME=admin
AUTH_PASSWORD=un-mot-de-passe-solide
```

`AUTH_OVERRIDE_FROM_ENV=true` remplace les identifiants admin au prochain démarrage (rotation). `RESET_AUTH=true` permet une récupération sans détruire les données. Ne les laissez pas à `true` en permanence.

L’ancienne variable `CAN_CHANGE_KEYS` est **ignorée**.

### LLM (Ollama)

Variables exactes du code : `LLM`, `OLLAMA_URL`, `OLLAMA_MODEL` (`get_env.py`, `user-config-env.cjs`). `START_OLLAMA` ne sert que l’entrée Docker `start.js` : laissez-le à `false` (Ollama tourne déjà ailleurs).

Exemple de configuration Ollama :

```bash
LLM=ollama
OLLAMA_URL=http://IP_OLLAMA:11434
OLLAMA_MODEL=qwen3.5:9b
START_OLLAMA=false
```

Forme de `OLLAMA_URL` (code + tests unitaires `test_ollama_transport_security.py`) :

- **Préfixe de chemin accepté.** Le README le dit explicitement (« proxy path prefixes are supported »). Un test envoie `OLLAMA_URL=http://ollama.internal:11434/private/proxy/` vers `…/private/proxy/api/tags`. Un préfixe de chemin est donc valide.
- **Sans slash final.** `_get_ollama_url()` le retire avant d’ajouter `/api/tags` et `/api/pull`. En revanche le client de génération (`llm_config.py`) fait `(OLLAMA_URL or "http://localhost:11434") + "/v1"` **sans** retirer le slash : `http://IP_OLLAMA:11434/` deviendrait `http://IP_OLLAMA:11434//v1`. Mettez l’URL **sans** `/` final.
- **Sans suffixe `/api`.** Presenton ajoute lui-même `/api/tags` et `/api/pull`.
- Pas de query ni de fragment. Les **redirections HTTP ne sont pas suivies** (erreur 502). Un éventuel reverse proxy devant Ollama doit servir l’API directement, sans 301/302 vers une autre URL.

Vérification à lancer **depuis le homelab** :

```bash
curl -sS -m 10 http://IP_OLLAMA:11434/api/version
curl -sS -m 10 http://IP_OLLAMA:11434/api/tags
```

Un `api/tags` réussi renvoie un JSON `{"models":[...]}`. Reprenez le champ `name` / `model` pour `OLLAMA_MODEL`.

Si le préfixe posait problème (peu probable), basculez sur le fournisseur **custom** (API OpenAI, l’URL **doit** alors inclure `/v1`) :

```bash
LLM=custom
CUSTOM_LLM_URL=http://IP_OLLAMA:11434/v1
CUSTOM_LLM_API_KEY=ollama
CUSTOM_MODEL=qwen3.5:9b
```

#### Modèles Ollama recommandés / supportés

Le catalogue « testé » est dans `servers/fastapi/constants/supported_ollama_models.py` (`SUPPORTED_OLLAMA_MODELS` = `TESTED_OLLAMA_MODELS`). Tout modèle **déjà présent** sur le serveur Ollama peut aussi être utilisé (il apparaît alors comme non testé, mais `check_llm_and_image_provider_api_or_model_availability` l’accepte).

Familles listées par Presenton : Llama 3 / 3.1 / 3.2 / 3.3 / 4, Gemma 3 et 4, DeepSeek R1, Qwen 3 et 3.5, GPT-OSS.

Le modèle recommandé ici est **`qwen3.5:9b`** (~6,6 Go dans le catalogue Presenton). Vérifiez qu’il est bien présent (`curl …/api/tags`) ; sinon : `ollama pull qwen3.5:9b`.

Le README officiel prend `llama3.2:3b` (environ 2 Go) comme exemple, y compris avec GPU. Autres suggestions (après `ollama pull <nom>`) :

| Situation | Modèle à tirer | Taille indiquée par Presenton |
| --- | --- | --- |
| Point de départ / machine limitée | `llama3.2:3b` | 2 GB |
| Bon compromis homelab (8 Go VRAM environ) | `llama3.1:8b` ou `qwen3:8b` | 4,9 / 5,2 GB |
| **Choix recommandé** | **`qwen3.5:9b`** | **6,6 GB** |
| Alternative plus large | `gemma3:12b` | 8,1 GB |
| Gros GPU | `qwen3:32b`, `llama3.3:70b`, `gpt-oss:20b` | 20 / 43 / 14 GB |

`llama3.2:1b`, `qwen3:4b` et `gemma3:4b` restent utilisables mais la qualité des outlines/slides sera plus faible. Les DeepSeek R1 sont des modèles « reasoning », souvent plus lents.

### Images : ComfyUI (Ollama images non disponible)

`IMAGE_PROVIDER` **n’inclut pas** `ollama`. Valeurs natives : `pexels`, `pixabay`, `gemini_flash`, `nanobanana_pro`, `gpt-image-2`, `gpt-image-2.5-flare`, `gpt-image-2.5-sunburst`, `comfyui`, `open_webui`, `openai_compatible`.

Le pont `openai_compatible` vers Ollama (`POST …/v1/images/generations`) est souvent inutilisable : la génération d’images Ollama est expérimentale, surtout visée macOS, et a été « temporarily removed » à partir d’Ollama 0.32.6 (août 2026). Ce n’est pas un bug de Presenton.

La voie retenue est donc **`IMAGE_PROVIDER=comfyui`**, avec deux PC Windows 11 Pro sur le LAN (RTX 5070 Ti 16 Go principale, RTX 3070 Ti 8 Go en secours). Les variables côté Presenton :

```bash
IMAGE_PROVIDER=comfyui
COMFYUI_URL=http://127.0.0.1:8188
ENABLE_PARALLEL_IMAGE_GENERATION=false
```

`COMFYUI_WORKFLOW` doit être une **chaîne JSON** (format API ComfyUI), pas un chemin de fichier. systemd `EnvironmentFile` gère mal un JSON multiligne : le script `/opt/presenton/scripts/presenton-fastapi-start.sh` lit `/etc/presenton/comfyui-workflow.json` et exporte la variable au lancement. Ne collez pas le JSON dans `presenton.env`.

Procédure complète (install Windows, pare-feu, modèle, nginx, tests) : section **10**.

### Mem0, Community, télémétrie

- `MEM0_ENABLED=true` : Mem0 reprend `OLLAMA_URL` / `OLLAMA_MODEL` s’ils sont définis, et ajoute `/v1` tout seul. Le `.env` d’exemple fixe aussi `MEM0_LLM_BASE_URL=http://IP_OLLAMA:11434` et `MEM0_LLM_MODEL=qwen3.5:9b`.
- `PRESENTON_COMMUNITY_ENABLED=false` pour un homelab / réseau isolé (pas d’appels à `api.presenton.ai`).
- `DISABLE_ANONYMOUS_TRACKING=true` pour couper la télémétrie anonyme.

Le fichier `presenton.env.example` liste aussi Vertex, Azure, Bedrock, OpenRouter, la recherche web (SearXNG, Tavily, Exa, Brave, Serper), etc.

---

## 10. Images avec ComfyUI (deux PC Windows 11 Pro)

Les deux machines GPU sont sous **Windows 11 Pro**. Utilisez les placeholders **`IP_5070TI`** et **`IP_3070TI`**, puis donnez à chaque PC une **IP fixe** ou une **réservation DHCP** (même réseau local que Presenton et Ollama).

Presenton n’accepte **qu’une** `COMFYUI_URL`. Le code (`servers/fastapi/utils/image_generation_service.py`) enchaîne, en HTTP uniquement (pas de WebSocket) :

1. `POST {url}/prompt` avec `{"prompt": <workflow>, "client_id": …}`
2. sondage `GET {url}/history/{prompt_id}` toutes les 4 s (délai max 3000 s)
3. téléchargement `GET {url}/view?filename=…&type=output`

L’historique et les fichiers de sortie sont **locaux à chaque instance**. `/prompt` puis `/history` et `/view` doivent donc frapper **le même** ComfyUI.

C’est pourquoi le bon schéma n’est **pas** un `least_conn` / `round-robin` (la 2ᵉ requête irait souvent sur l’autre GPU : 404 ou attente infinie) ni un `ip_hash` (Presenton n’a qu’une IP source, tout le trafic resterait collé à une seule carte, la seconde ne servirait jamais). Le schéma retenu est un upstream nginx **actif / passif** : la RTX **5070 Ti** (16 Go, Blackwell) est le serveur principal ; la RTX **3070 Ti** (8 Go) n’est utilisée que si la première est injoignable (`backup`).

`COMFYUI_URL=http://127.0.0.1:8188` pointe vers ce proxy, qui n’écoute **que** en local sur la machine Presenton (ComfyUI n’est pas exposé sur Internet).

Le nœud de prompt du workflow doit s’intituler exactement **`Input Prompt`** (casse ignorée). Sinon Presenton lève : `Could not find node with title 'Input Prompt'. Rename your prompt node to 'Input Prompt'.` (un commentaire du code mentionne encore « Positive » : c’est obsolète). Presenton randomise les graines et injecte largeur / hauteur dans les nœuds `EmptyLatentImage`, `EmptySD3LatentImage`, ou un nœud titré « Image Size ». Le JSON doit être au **format API** (identifiants de nœuds → `{class_type, inputs, _meta}`), pas le format « Save » de l’interface.

### 10.1 Même modèle sur les deux cartes : SDXL Turbo

Un seul workflow doit fonctionner des deux côtés, sinon le basculement casse. Le facteur limitant est la **8 Go** de la 3070 Ti. Flux / Z-Image Turbo tiennent mieux sur 16 Go et sont trop lourds pour un secours fiable.

Modèle commun : **SDXL Turbo** fp16, 4 pas, `cfg 1.0`, sampler `euler`, scheduler `sgm_uniform`, typiquement 1024×1024.

Fichier checkpoint à placer dans `ComfyUI\models\checkpoints\` **sur les deux PC** :

- nom attendu par le workflow fourni : `sd_xl_turbo_1.0_fp16.safetensors`
- source : [stabilityai/sdxl-turbo](https://huggingface.co/stabilityai/sdxl-turbo/blob/main/sd_xl_turbo_1.0_fp16.safetensors)

Le workflow API est `comfyui/sdxl-turbo-api-workflow.json`.

### 10.2 Installation de ComfyUI sur chaque PC (Windows 11 Pro)

Identique sur la 5070 Ti et la 3070 Ti.

1. Installez un **pilote NVIDIA récent** (Game Ready ou Studio). La 5070 Ti (Blackwell, sm_120) exige un pilote récent (série R580 ou plus récente). Le paquet portable officiel NVIDIA de fin 2026 embarque typiquement **Python 3.13** et **CUDA 13.0 / cu130** (le minimum historique pour Blackwell était CUDA 12.8 / cu128 ; le portable actuel va plus loin et convient aussi à la 3070 Ti).
2. Téléchargez le **portable NVIDIA** depuis les [releases ComfyUI](https://github.com/comfyanonymous/ComfyUI/releases) (`ComfyUI_windows_portable_nvidia…`). Extraire, par exemple dans `C:\AI\ComfyUI_windows_portable`.
3. Copiez `sd_xl_turbo_1.0_fp16.safetensors` dans `ComfyUI\models\checkpoints\`.
4. Copiez `run-comfyui-lan.bat`, `run-comfyui-lan-debug.bat`, `install-firewall-lan.ps1` et `install-autostart-task.ps1` à la **racine** du portable (à côté de `python_embeded` et de `run_nvidia_gpu.bat`).
5. Premier lancement interactif : double-cliquez `run-comfyui-lan-debug.bat`. L’UI doit répondre sur `http://127.0.0.1:8188`. Vérifiez qu’un essai de génération avec SDXL Turbo aboutit (surtout sur la 3070 Ti, pour confirmer la VRAM).
6. Pare-feu, **PowerShell en administrateur** (limite le port **TCP 8188** au réseau local ; ajustez `192.168.1.0/24` si ce n’est pas votre plage d’adresses) :

```powershell
powershell -ExecutionPolicy Bypass -File .\install-firewall-lan.ps1
# éventuellement : -RemoteAddress "192.168.1.0/24"
```

7. Démarrage automatique au boot (tâche planifiée, compte SYSTEM, sans `pause`) :

```powershell
powershell -ExecutionPolicy Bypass -File .\install-autostart-task.ps1
Start-ScheduledTask -TaskName "ComfyUI Presenton"
```

Alternative service Windows : [NSSM](https://nssm.cc/) (`install-autostart-task.ps1` contient un exemple de commandes).

8. Attribuez une **IP fixe** ou une **réservation DHCP** à chaque machine, puis notez `IP_5070TI` et `IP_3070TI`.

Le `.bat` de service lance :

```text
python_embeded\python.exe -s ComfyUI\main.py --listen 0.0.0.0 --port 8188 --windows-standalone-build
```

Sans `--listen 0.0.0.0`, ComfyUI n’écouterait que localhost et serait injoignable depuis l’hôte Presenton. N’ouvrez **pas** le port 8188 vers Internet.

### 10.3 Proxy nginx sur l’hôte Presenton (Debian 13)

```bash
# Après avoir remplacé IP_5070TI et IP_3070TI :
sudo cp comfyui/nginx-comfyui-upstream.conf /etc/nginx/sites-available/comfyui-presenton
sudo nano /etc/nginx/sites-available/comfyui-presenton
sudo ln -sfn /etc/nginx/sites-available/comfyui-presenton /etc/nginx/sites-enabled/comfyui-presenton
sudo nginx -t && sudo systemctl reload nginx
```

L’`install.sh` copie déjà ce fichier dans `sites-available`, **sans l’activer**, tant que les placeholders sont là.

Extrait de l’upstream :

```nginx
upstream comfyui_presenton {
  server IP_5070TI:8188 max_fails=2 fail_timeout=15s;
  server IP_3070TI:8188 backup;
}

server {
  listen 127.0.0.1:8188;
  listen [::1]:8188;
  # proxy_read_timeout 3100s  (Presenton peut poller /history jusqu'à 3000 s)
  ...
}
```

Workflow sur l’hôte Presenton (déjà fait par `install.sh` s’il n’existe pas encore) :

```bash
sudo comfyui/install-workflow-on-presenton.sh
sudo systemctl restart presenton-fastapi
```

### 10.4 Tests depuis l’hôte Presenton

```bash
# Santé de chaque GPU, puis du proxy local (remplacez les IP) :
curl -sS -m 5 http://IP_5070TI:8188/system_stats
curl -sS -m 5 http://IP_3070TI:8188/system_stats
curl -sS -m 5 http://127.0.0.1:8188/system_stats

# Script tout-en-un (POST /prompt avec le workflow) :
IP_5070TI=192.168.1.10 IP_3070TI=192.168.1.11 \
  sudo -u presenton comfyui/test-comfyui-from-presenton.sh
```

Pour vérifier le secours : arrêtez ComfyUI sur la 5070 Ti, relancez le `curl` vers `http://127.0.0.1:8188/system_stats` — nginx doit basculer sur la 3070 Ti (parfois après `fail_timeout`, ici 15 s).

---

## 11. Reverse proxy nginx

Le `nginx.conf` du dépôt est un fichier **principal** prévu pour le conteneur (`user www-data`, chemins `/app` et `/app_data`, `listen 80`). Sur un homelab, il ne faut **pas** remplacer `/etc/nginx/nginx.conf`. Utilisez un **site** + un petit fichier `map` :

```bash
sudo cp nginx/presenton-maps.conf /etc/nginx/conf.d/presenton-maps.conf
sudo cp nginx/presenton.conf     /etc/nginx/sites-available/presenton
sudo ln -sfn /etc/nginx/sites-available/presenton /etc/nginx/sites-enabled/presenton
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

Le site fourni écoute sur le **port 5001** (IPv4 et IPv6) pour éviter un conflit avec un site déjà présent sur le port 80. Adaptez `listen` / `server_name` si vous préférez le port 80, ou placez Presenton derrière un proxy existant (Nginx Proxy Manager, Caddy, Traefik). Dans tous les cas, réglez `PRESENTON_PUBLIC_URL` sur l’URL vue dans le navigateur.

Rôles repris fidèlement du `nginx.conf` amont :

- `/` → Next.js `:3000` (WebSocket, timeouts 30 min, `Host $http_host` pour conserver le port)
- `/api/v1/` et `/api/v2/` → FastAPI `:8000` (taille d’upload 110 Mo sur v1)
- `/mcp` et `/mcp/` → MCP `:8001`, avec `Host localhost:8001` (allowlist FastMCP)
- `/docs` et `/openapi.json` → FastAPI (accessibles une fois authentifié)
- `/static/` → fichiers empaquetés (alias vers `/opt/presenton/servers/fastapi/static/`)
- `/app_data/{images,exports,uploads,pptx-to-html,pptx-to-json}/` servis par nginx, **protégés** par `auth_request` vers `/api/v1/auth/verify`
- `/app_data/{fonts,templates}/` servis directement

Les slashs finaux des `location` / `alias` sont **volontaires** (le dépôt documente un risque de lecture de fichiers hors cible si on écrit `/static` sans slash).

Si vous avez déjà un nginx et qu’un autre site occupe 5001, changez le `listen` ou désactivez le site en conflit. Ne lancez pas `node start.js` sur l’hôte : ce script exécute `service nginx start` et vise `/etc/nginx/nginx.conf` comme dans Docker.

---

## 12. Services systemd (démarrage automatique)

Fichiers à copier depuis `systemd/` :

```bash
sudo cp systemd/presenton-*.service systemd/presenton.target \
  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now presenton.target
sudo systemctl status presenton-fastapi presenton-nextjs presenton-mcp nginx
```

Unités :

- `presenton-fastapi.service` — `/opt/presenton/scripts/presenton-fastapi-start.sh` (charge `/etc/presenton/comfyui-workflow.json` dans `COMFYUI_WORKFLOW`, puis lance `server.py` sur le port 8000)
- `presenton-mcp.service` — `mcp_server.py --port 8001` (après FastAPI)
- `presenton-nextjs.service` — `node …/standalone/server.js` avec `HOSTNAME=127.0.0.1` et `PORT=3000`
- `presenton.target` — les trois ensemble, activable au boot

Toutes lisent `EnvironmentFile=/etc/presenton/presenton.env` et tournent sous l’utilisateur `presenton`. Les trois ports applicatifs restent liés à `127.0.0.1`.

```bash
journalctl -u presenton-fastapi -u presenton-nextjs -u presenton-mcp -f
```

---

## 13. Premier démarrage

1. Ouvrir `http://<hôte>:5001`.
2. Créer le compte admin si vous n’avez pas défini `AUTH_*`.
3. Dans Paramètres, choisir le fournisseur LLM et, le cas échéant, le fournisseur d’images.
4. (Optionnel) Swagger : `http://<hôte>:5001/docs` une fois connecté.

Connexion API (cookie `presenton_session`) :

```bash
curl -sS -c cookies.txt -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"votre-mot-de-passe"}' \
  http://127.0.0.1:5001/api/v1/auth/login
```

---

## 14. Mises à jour

```bash
sudo systemctl stop presenton.target
sudo -u presenton -H bash -c '
  set -euo pipefail
  cd /opt/presenton
  git fetch --tags origin
  git checkout main          # ou un tag précis
  git pull --ff-only origin main

  cd /opt/presenton/servers/fastapi
  uv python install 3.11
  uv sync --frozen --no-dev
  uv pip install "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"

  cd /opt/presenton
  npm ci
  node scripts/sync-document-dependencies.cjs
  node scripts/sync-presentation-export.cjs --force

  cd /opt/presenton/servers/nextjs
  npm ci
  npm run build
  cp -a .next-build/static .next-build/standalone/.next-build/static
'
sudo systemctl start presenton.target
# Les migrations Alembic se relancent toutes seules si MIGRATE_DATABASE_ON_STARTUP=true
```

Faites une copie de `/var/lib/presenton/app_data` (surtout `fastapi.db` et `userConfig.json`) avant une mise à jour importante.

---

## 15. Dépannage

| Symptôme | Piste |
| --- | --- |
| `requires-python >=3.11,<3.12` / mauvais interpréteur | Le `python3` Debian est 3.13. Utiliser `uv python install 3.11` et le binaire `.venv/bin/python`. |
| Build Next.js / `sharp` / lockfile | Node 22 + npm 11.16.0. Le Node 20 Debian n’est pas celui du `Dockerfile`. |
| `"next start" does not work with output: standalone` | Lancer `node /opt/presenton/servers/nextjs/.next-build/standalone/server.js` après copie de `.next-build/static`. |
| Page blanche / CSS 404 en standalone | `assemble-nextjs-standalone.sh` (copie de `.next-build/static` dans `standalone/.next-build/static`). |
| `presentation-export runtime is missing` | `node scripts/sync-presentation-export.cjs --force` depuis la racine, et `EXPORT_PACKAGE_ROOT` correct. |
| Export PDF/PPTX échoue | `PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium`, paquets `chromium` + polices, assez de RAM, `/dev/shm` accessible. |
| Images `/app_data/...` en 401 | Session absente (cookie). Un fichier authentifié doit passer en 200 ; un listing de dossier peut renvoyer 403 (pas d’autoindex). |
| MCP en 401 | Normal sans clé API Bearer. Le `Host` interne doit rester `localhost:8001`. |
| Mem0 se plaint de spaCy / Ollama | Installer `en_core_web_sm` 3.8.0 ; régler `MEM0_LLM_BASE_URL` ou `MEM0_ENABLED=false`. |
| Redirections Next.js cassées (mauvais port) | nginx doit envoyer `Host $http_host` (pas `$host`). `PRESENTON_PUBLIC_URL` doit correspondre à l’URL publique. |
| Conflit de port 5001 | Changer le `listen` du site nginx et `PRESENTON_PUBLIC_URL`. |
| Images ComfyUI : `Could not find node with title 'Input Prompt'` | Le workflow n’est pas au format API, ou le nœud CLIPTextEncode n’a pas le titre exact `Input Prompt`. Utilisez `comfyui/sdxl-turbo-api-workflow.json`. |
| `COMFYUI_WORKFLOW` vide / JSON invalide au démarrage | Le JSON doit être chargé par `presenton-fastapi-start.sh` depuis `/etc/presenton/comfyui-workflow.json`, pas collé dans l’`EnvironmentFile`. |
| `/history` ou `/view` en 404, génération qui tourne dans le vide | Les requêtes n’atteignent pas la même instance. Vérifiez que `COMFYUI_URL` pointe vers le proxy `127.0.0.1:8188` (actif/passif), pas un `least_conn` / `round-robin`. |
| Proxy 127.0.0.1:8188 injoignable | Site `comfyui-presenton` non activé, ou placeholders `IP_5070TI` / `IP_3070TI` non remplacés. `sudo nginx -t`. |
| 5070 Ti OK en direct, proxy bloqué / timeout | Pare-feu Windows trop strict (autoriser TCP 8188 depuis votre réseau local, par ex. `192.168.1.0/24`), ComfyUI lancé sans `--listen 0.0.0.0`, ou IP a changé (réservation DHCP). |

---

## 16. Ce qui a été vérifié sur une machine de test Debian 13

Tests réalisés le 24 novembre 2026 (Europe/Paris) sur une machine Debian 13 de test. Le dépôt amont [presenton/presenton](https://github.com/presenton/presenton) a été cloné pour vérifier le build et les services.

| Étape | Résultat |
| --- | --- |
| `uv python install 3.11` puis `uv sync --frozen --no-dev` | OK, Python **3.11.18**, venv fonctionnel |
| Roue spaCy `en_core_web_sm-3.8.0` | OK |
| `scripts/warm_fastembed_cache.py` | OK (`BAAI/bge-small-en-v1.5`, `Qdrant/bm25`, cache icônes) |
| `npm ci` racine + `sync-document-dependencies` + export-core **1.0.51** | OK (Node de la box : v24.22.1 / npm 11.21.1 — le couple officiel reste Node 22 + npm 11.16.0) |
| `npm ci` et `npm run build` dans `servers/nextjs` (Next.js **16.4.6**) | OK ; un avertissement Turbopack sur un accès disque dynamique, build réussi |
| FastAPI `server.py --port 8000` | OK : migrations Alembic, import des 16 templates, bootstrap admin via `AUTH_*`, `GET /api/v1/auth/status` → `configured: true` |
| Login `POST /api/v1/auth/login` | OK, cookie `presenton_session`, `/docs` passe de 401 à 200 |
| MCP `mcp_server.py --port 8001` | OK, FastMCP 4.1.2 sur `/mcp` (401 sans Bearer, attendu) |
| `node .next-build/standalone/server.js` | OK : `/`, `/settings`, CSS et `/Logo.png` en 200 |
| `next start` | Démarre mais affiche l’avertissement officialisant le mode standalone |
| nginx 1.26.3 en reverse proxy sur `:5001` | OK après ajout de répertoires temporaires (test en utilisateur non root). UI, API, login, `/docs`, `/static`, CSS : 200. `/app_data/images/fichier` : 401 sans cookie, 200 avec session |

Non testé de bout en bout : génération réelle d’une présentation, export PPTX/PDF via Chromium, GPU, NodeSource (Node 22 prescrit par le dépôt ; build validé avec Node 24 déjà présent). La connexion à un Ollama distant doit être vérifiée depuis le homelab (`curl` vers `http://IP_OLLAMA:11434/api/tags`).

---

## 17. Checklist après installation

1. **Adresses IP** des deux PC GPU : remplacer les placeholders **`IP_5070TI`** et **`IP_3070TI`** dans `/etc/nginx/sites-available/comfyui-presenton`, puis activer le site. Donnez à chaque machine une **IP fixe** ou une **réservation DHCP**.
2. Installer ComfyUI (portable NVIDIA), le checkpoint **SDXL Turbo**, le pare-feu du réseau local et la tâche de démarrage sur **les deux** PC (section 10).
3. Renseigner l’**URL publique** de Presenton (`PRESENTON_PUBLIC_URL`, ex. `http://IP_PRESENTON:5001` ou un nom en HTTPS).
4. Dans `/etc/presenton/presenton.env`, remplacer `IP_OLLAMA` par l’adresse de ton serveur Ollama (port par défaut **11434**, ou `http://127.0.0.1:11434` s’il est sur la même machine). Confirmer que `qwen3.5:9b` (ou le modèle choisi) est bien tiré (`curl http://IP_OLLAMA:11434/api/tags` / `ollama pull qwen3.5:9b` si besoin).
5. Puis : `sudo ./install.sh` (si ce n’est pas déjà fait), relecture du `.env`, `sudo systemctl enable --now presenton.target` et `sudo systemctl reload nginx`.
