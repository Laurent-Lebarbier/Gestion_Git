#!/bin/bash
# =============================================================
# clone_repos.sh — Clone tous les dépôts GitHub en local
# Usage : bash clone_repos.sh [--path /chemin]
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps curl git jq flock
detect_env
acquire_lock

DEFAULT_BRANCH="main"
CLONE_DIR="$BASE_PATH"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) CLONE_DIR="$2"; shift 2 ;;
        *) echo "Option inconnue : $1"; exit 1 ;;
    esac
done

echo "=== Clonage des dépôts GitHub vers $ENV_LABEL : $CLONE_DIR ==="

if [ ! -d "$CLONE_DIR" ]; then
    echo "Création du répertoire $CLONE_DIR..."
    mkdir -p "$CLONE_DIR" || { echo "❌ Impossible de créer $CLONE_DIR"; exit 1; }
fi

echo "Récupération de la liste des dépôts de $GITHUB_USER..."
mapfile -t repos < <(github_list_repos)

if [ ${#repos[@]} -eq 0 ]; then
    echo "❌ Aucun dépôt trouvé. Vérifiez le token GitHub (scope 'repo' requis)."
    exit 1
fi
echo "  → ${#repos[@]} dépôt(s) trouvé(s)."

success=0
skipped=0
errors=0

for repo_name in "${repos[@]}"; do
    is_excluded_repo "$repo_name" && continue
    repo_path="$CLONE_DIR/$repo_name"
    echo ""
    echo "📁 $repo_name"

    if [ -d "$repo_path/.git" ]; then
        echo "  ℹ️  Déjà cloné, mise à jour..."
        if (cd "$repo_path" && check_repo_ready "$repo_name" && pull_ff_only "$(current_branch "$DEFAULT_BRANCH")"); then
            success=$((success + 1))
        else
            skipped=$((skipped + 1))
        fi
        continue
    fi

    if [ -e "$repo_path" ]; then
        echo "  ⚠️  $repo_path existe déjà sans Git — ignoré (utilisez sync_initial.sh)."
        skipped=$((skipped + 1))
        continue
    fi

    clone_url="git@github.com:$GITHUB_USER/$repo_name.git"
    echo "  → Clonage depuis $clone_url..."
    if git clone -q "$clone_url" "$repo_path"; then
        echo "  ✅ Cloné dans $repo_path"
        success=$((success + 1))
    else
        echo "  ❌ Échec du clonage."
        errors=$((errors + 1))
    fi
done

echo ""
echo "=== Clonage terminé : $success réussi(s), $skipped ignoré(s), $errors erreur(s) ==="
