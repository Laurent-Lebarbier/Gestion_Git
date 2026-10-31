#!/bin/bash
# =============================================================
# pull_repos.sh — Récupère les dernières modifications depuis GitHub
# (avance rapide uniquement : ne crée jamais de merge implicite)
# Usage : bash pull_repos.sh [--path /chemin] [nom_repo]
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps git flock
detect_env
acquire_lock

DEFAULT_BRANCH="main"
FILTER_REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) BASE_PATH="$2"; shift 2 ;;
        --*) echo "Option inconnue : $1"; exit 1 ;;
        *) FILTER_REPO="$1"; shift ;;
    esac
done

echo "=== Pull vers $ENV_LABEL : $BASE_PATH ==="

if [ ! -d "$BASE_PATH" ]; then
    echo "❌ Le chemin $BASE_PATH n'existe pas."
    exit 1
fi

pull_one_repo() {
    local repo_name branch
    repo_name=$(basename "$PWD")
    check_repo_ready "$repo_name" || return 1
    branch=$(current_branch "$DEFAULT_BRANCH")

    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "  ℹ️  Modifications locales non commitées (elles sont conservées)."
    fi
    pull_ff_only "$branch"
}

success=0
errors=0

for dir in "$BASE_PATH"/*/; do
    [ -d "$dir" ] || continue
    repo_name=$(basename "$dir")
    if [ -n "$FILTER_REPO" ]; then
        [ "$repo_name" != "$FILTER_REPO" ] && continue
    else
        is_excluded_repo "$repo_name" && continue
    fi

    echo ""
    echo "📁 $repo_name"
    if (cd "$dir" && pull_one_repo); then
        success=$((success + 1))
    else
        errors=$((errors + 1))
    fi
done

echo ""
echo "=== Pull terminé : $success réussi(s), $errors erreur(s) ==="
[ "$errors" -eq 0 ]
