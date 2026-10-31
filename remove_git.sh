#!/bin/bash
# =============================================================
# remove_git.sh — Supprime les dossiers .git des dépôts locaux
# Usage : bash remove_git.sh [--path /chemin]
# ATTENTION : Ceci délie les dossiers de Git (pas de suppression GitHub)
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps flock

detect_env
acquire_lock
BASE_DIR="$BASE_PATH"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) BASE_DIR="$2"; shift 2 ;;
        *) echo "Option inconnue : $1"; exit 1 ;;
    esac
done

echo "=== Suppression des dossiers .git dans : $BASE_DIR ==="
echo "⚠️  Cela supprime le suivi Git local (GitHub n'est pas affecté)."
read -rp "Confirmer ? (oui/non) : " confirm
[ "$confirm" != "oui" ] && echo "Annulé." && exit 0

removed=0
skipped=0

for repo in "$BASE_DIR"/*/; do
    [ -d "$repo" ] || continue
    repo_name=$(basename "$repo")
    is_excluded_repo "$repo_name" && continue

    if [ -d "$repo/.git" ]; then
        echo "  🗑️  Suppression .git dans : $repo_name"
        rm -rf "$repo/.git"
        removed=$((removed + 1))
    else
        echo "  ℹ️  Pas de .git dans : $repo_name"
        skipped=$((skipped + 1))
    fi
done

echo ""
echo "=== Terminé : $removed supprimé(s), $skipped ignoré(s) ==="
