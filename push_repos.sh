#!/bin/bash
# =============================================================
# push_repos.sh — Commit les changements locaux et push vers GitHub
# Usage : bash push_repos.sh [--path /chemin] [--message "Mon message"] [nom_repo]
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps git flock
detect_env
acquire_lock

DEFAULT_BRANCH="main"
COMMIT_MSG="Mise à jour automatique — $(date '+%Y-%m-%d %H:%M')"
FILTER_REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) BASE_PATH="$2"; shift 2 ;;
        --message) COMMIT_MSG="$2"; shift 2 ;;
        --*) echo "Option inconnue : $1"; exit 1 ;;
        *) FILTER_REPO="$1"; shift ;;
    esac
done

echo "=== Push depuis $ENV_LABEL : $BASE_PATH ==="

if [ ! -d "$BASE_PATH" ]; then
    echo "❌ Le chemin $BASE_PATH n'existe pas."
    exit 1
fi

push_one_repo() {
    local repo_name branch
    repo_name=$(basename "$PWD")
    check_repo_ready "$repo_name" || return 1
    branch=$(current_branch "$DEFAULT_BRANCH")
    commit_and_push "$branch" "$COMMIT_MSG"
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
    if (cd "$dir" && push_one_repo); then
        success=$((success + 1))
    else
        errors=$((errors + 1))
    fi
done

echo ""
echo "=== Push terminé : $success réussi(s), $errors erreur(s) ==="
[ "$errors" -eq 0 ]
