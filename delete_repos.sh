#!/bin/bash
# =============================================================
# delete_repos.sh — Supprime des dépôts GitHub (avec confirmation)
# Usage : bash delete_repos.sh [nom_repo1 nom_repo2 ...]
#         Sans argument : liste et supprime TOUS les dépôts (dangereux !)
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps curl jq

echo "=== Suppression de dépôts GitHub pour $GITHUB_USER ==="
echo "⚠️  ATTENTION : Cette opération est irréversible !"

# Si des noms sont passés en argument, on les utilise
# Sinon on récupère tous les dépôts
if [ $# -gt 0 ]; then
    repos=("$@")
    echo "Dépôts ciblés : ${repos[*]}"
else
    echo "Récupération de la liste complète des dépôts..."
    mapfile -t repos < <(github_list_repos)

    if [ ${#repos[@]} -eq 0 ]; then
        echo "❌ Aucun dépôt trouvé."
        exit 1
    fi

    echo "Dépôts trouvés (${#repos[@]}) :"
    printf '  - %s\n' "${repos[@]}"
fi

echo ""
echo "⚠️  Ces dépôts seront DÉFINITIVEMENT supprimés de GitHub."
read -rp "Tapez 'SUPPRIMER' pour confirmer : " confirmation

if [ "$confirmation" != "SUPPRIMER" ]; then
    echo "Opération annulée."
    exit 0
fi

success=0
errors=0

for repo_name in "${repos[@]}"; do
    echo ""
    echo "🗑️  Suppression de $repo_name..."

    # Vérifier que le dépôt existe
    if ! github_repo_exists "$repo_name"; then
        echo "  ⚠️  Dépôt $repo_name introuvable sur GitHub, ignoré."
        continue
    fi

    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X DELETE \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$GITHUB_USER/$repo_name")

    if [ "$http_code" -eq 204 ]; then
        echo "  ✅ $repo_name supprimé."
        success=$((success + 1))
    else
        echo "  ❌ Échec suppression $repo_name (HTTP $http_code)."
        errors=$((errors + 1))
    fi
done

echo ""
echo "=== Suppression terminée : $success réussi(s), $errors erreur(s) ==="
