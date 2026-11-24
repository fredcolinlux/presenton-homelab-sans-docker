# ComfyUI pour Presenton (deux GPU Windows 11 Pro)

Voir le tutoriel : [README.md](../README.md) (partie ComfyUI) et le guide technique : [docs/INSTALL-TECHNIQUE.md](../docs/INSTALL-TECHNIQUE.md) (section 10).

- `sdxl-turbo-api-workflow.json` — workflow au **format API** (nœud intitulé exactement `Input Prompt`).
- `run-comfyui-lan.bat` / `run-comfyui-lan-debug.bat` — à copier à la racine du portable ComfyUI.
- `install-firewall-lan.ps1` — pare-feu TCP 8188 limité au réseau local (adaptez `-RemoteAddress`).
- `install-autostart-task.ps1` — tâche planifiée au démarrage (compte SYSTEM).
- `nginx-comfyui-upstream.conf` — sur la machine Presenton : 5070 Ti principale, 3070 Ti en `backup`. Remplacer `IP_5070TI` et `IP_3070TI`.
- `install-workflow-on-presenton.sh` et `test-comfyui-from-presenton.sh` — côté Debian 13.
