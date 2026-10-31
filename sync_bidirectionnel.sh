#!/bin/bash
# =============================================================
# sync_bidirectionnel.sh — Synchronisation bidirectionnelle
# WSL (local) <——> GitHub <——> OVH (serveur)
#
# Pour chaque dépôt :
#   1. Commit des changements locaux (ajouts, modifs, suppressions)
#   2. Rebase sur GitHub, puis push de tout commit en attente
#   3. Sinon, simple mise à jour depuis GitHub (avance rapide)
#
# Usage :
#   bash sync_bidirectionnel.sh              # tous les dépôts
#   bash sync_bidirectionnel.sh mon_repo     # un seul dépôt
#   bash sync_bidirectionnel.sh --pull-only  # seulement récupérer
#   bash sync_bidirectionnel.sh --push-only  # seulement envoyer
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps git flock
detect_env
acquire_lock

DEFAULT_BRANCH="main"
COMMIT_MSG="Sync auto [$ENV_LABEL] — $(date '+%Y-%m-%d %H:%M')"

FILTER_REPO=""
DO_PUSH=true
DO_PULL=true

for arg in "$@"; do
    case "$arg" in
        --pull-only) DO_PUSH=false ;;
        --push-only) DO_PULL=false ;;
        --*) echo "Option inconnue : $arg"; exit 1 ;;
        *) FILTER_REPO="$arg" ;;
    esac
done

if ! $DO_PUSH && ! $DO_PULL; then
    echo "❌ --pull-only et --push-only sont incompatibles."
    exit 1
fi

echo "======================================================"
echo "  Synchronisation bidirectionnelle — $ENV_LABEL"
echo "  Chemin : $BASE_PATH"
echo "  Push : $DO_PUSH | Pull : $DO_PULL"
[ -n "$FILTER_REPO" ] && echo "  Dépôt filtré : $FILTER_REPO"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

sync_one_repo() {
    local repo_name branch
    repo_name=$(basename "$PWD")

    check_repo_ready "$repo_name" || return 1
    branch=$(current_branch "$DEFAULT_BRANCH")

    if $DO_PUSH; then
        # commit_and_push fait déjà le fetch + rebase : le dépôt est à jour ensuite
        commit_and_push "$branch" "$COMMIT_MSG"
        return $?
    fi

    # --pull-only
    pull_ff_only "$branch"
}

if [ ! -d "$BASE_PATH" ]; then
    echo "❌ Le chemin $BASE_PATH n'existe pas."
    echo "   Vérifiez OVH_BASE_PATH / LOCAL_BASE_PATH dans .env"
    exit 1
fi

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

    # Sous-shell : chaque dépôt est isolé (pas de cd à défaire)
    if (cd "$dir" && sync_one_repo); then
        success=$((success + 1))
    else
        errors=$((errors + 1))
    fi
done

echo ""
echo "======================================================"
echo "  Sync terminée : $success réussi(s), $errors erreur(s)"
echo "======================================================"
[ "$errors" -eq 0 ]
