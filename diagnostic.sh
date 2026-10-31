#!/bin/bash
# =============================================================
# diagnostic.sh — Vérifie l'état de tous les dépôts (lecture seule,
# à part un "git fetch" pour connaître l'état de GitHub)
# Affiche ce qui est en avance, en retard, divergent ou bloqué.
#
# Usage : bash diagnostic.sh
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps git curl jq
detect_env

DEFAULT_BRANCH="main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OK=0
WARN=0
ERR=0

echo "======================================================"
echo "  DIAGNOSTIC GIT — $ENV_LABEL"
echo "  Chemin analysé : $BASE_PATH"
echo "  Date           : $(date '+%Y-%m-%d %H:%M')"
echo "======================================================"
echo ""

echo "Récupération des dépôts GitHub de $GITHUB_USER..."
github_repos=$(github_list_repos | sort)
if [ -z "$github_repos" ]; then
    echo -e "${RED}❌ Impossible de récupérer les dépôts GitHub. Vérifiez le token.${NC}"
    exit 1
fi
echo ""

if [ ! -d "$BASE_PATH" ]; then
    echo -e "${RED}❌ Le chemin $BASE_PATH n'existe pas.${NC}"
    exit 1
fi

echo "── Dépôts locaux dans $BASE_PATH ──────────────────────"
echo ""

for dir in "$BASE_PATH"/*/; do
    [ -d "$dir" ] || continue
    repo_name=$(basename "$dir")
    is_excluded_repo "$repo_name" && continue

    echo -e "${BLUE}📁 $repo_name${NC}"
    cd "$dir" || continue

    if [ ! -d ".git" ]; then
        echo -e "  ${RED}✗ Pas de dossier .git — non initialisé${NC}"
        ERR=$((ERR + 1)); echo ""; continue
    fi

    if rebase_in_progress; then
        echo -e "  ${RED}✗ Rebase/merge en cours — bloque la synchro (git status)${NC}"
        ERR=$((ERR + 1)); echo ""; continue
    fi

    if ! git symbolic-ref -q HEAD >/dev/null; then
        echo -e "  ${RED}✗ HEAD détaché${NC}"
        ERR=$((ERR + 1)); echo ""; continue
    fi

    branch=$(current_branch "$DEFAULT_BRANCH")
    echo "  Branche locale  : $branch"

    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$remote_url" ]; then
        echo -e "  ${RED}✗ Aucun remote 'origin' configuré${NC}"
        ERR=$((ERR + 1)); echo ""; continue
    fi
    echo "  Remote origin   : $remote_url"

    if ! echo "$github_repos" | grep -qx "$repo_name"; then
        echo -e "  ${YELLOW}⚠ Dépôt absent de GitHub${NC}"
        WARN=$((WARN + 1)); echo ""; continue
    fi
    echo -e "  GitHub          : ${GREEN}✓ présent${NC}"

    git fetch origin --quiet 2>/dev/null

    if ! remote_branch_exists "$branch"; then
        echo -e "  Commits         : ${YELLOW}⬆  origin/$branch n'existe pas — $(commits_ahead "$branch") commit(s) jamais pushés${NC}"
        echo "  → Action : bash push_repos.sh $repo_name"
        WARN=$((WARN + 1))
    else
        ahead=$(commits_ahead "$branch")
        behind=$(commits_behind "$branch")
        if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
            echo -e "  Commits         : ${GREEN}✓ À jour (en sync avec GitHub)${NC}"
            OK=$((OK + 1))
        elif [ "$behind" -eq 0 ]; then
            echo -e "  Commits         : ${YELLOW}⬆  $ahead commit(s) locaux non pushés${NC}"
            echo "  → Action : bash push_repos.sh $repo_name"
            WARN=$((WARN + 1))
        elif [ "$ahead" -eq 0 ]; then
            echo -e "  Commits         : ${YELLOW}⬇  $behind commit(s) distants non récupérés${NC}"
            echo "  → Action : bash pull_repos.sh $repo_name"
            WARN=$((WARN + 1))
        else
            echo -e "  Commits         : ${RED}⚡ DIVERGENCE — $ahead local / $behind distant${NC}"
            echo "  → Action : bash sync_bidirectionnel.sh $repo_name (rebase), sinon résolution manuelle"
            ERR=$((ERR + 1))
        fi
    fi

    modified=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$modified" -gt 0 ]; then
        echo -e "  Fichiers        : ${YELLOW}⚠  $modified fichier(s) non commités${NC}"
        git status --short | head -20 | sed 's/^/    /'
        [ "$modified" -gt 20 ] && echo "    … ($((modified - 20)) de plus)"
        WARN=$((WARN + 1))
    else
        echo -e "  Fichiers        : ${GREEN}✓ Aucune modification en attente${NC}"
    fi

    echo ""
done

echo "── Dépôts GitHub sans dossier local ───────────────────"
echo ""

while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    is_excluded_repo "$repo" && continue
    if [ ! -d "$BASE_PATH/$repo" ]; then
        echo -e "  ${YELLOW}⚠  $repo${NC} — présent sur GitHub, absent en local"
        echo "     → Action : bash clone_repos.sh"
        WARN=$((WARN + 1))
    fi
done <<< "$github_repos"

echo ""
echo "======================================================"
echo -e "  RÉSUMÉ : ${GREEN}$OK OK${NC}  |  ${YELLOW}$WARN avertissement(s)${NC}  |  ${RED}$ERR erreur(s)${NC}"
echo "======================================================"
echo ""

if [ "$ERR" -gt 0 ] || [ "$WARN" -gt 0 ]; then
    echo "Actions recommandées :"
    echo "  1. Lancer ce diagnostic sur l'autre machine aussi."
    echo "  2. État incertain partout ? → bash sync_initial.sh --dry-run puis sans --dry-run"
    echo "  3. Sinon, au quotidien    → bash sync_bidirectionnel.sh"
fi
