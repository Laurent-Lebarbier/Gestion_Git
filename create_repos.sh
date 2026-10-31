#!/bin/bash
# =============================================================
# create_repos.sh — Crée les dépôts GitHub et initialise les dépôts locaux
# Usage : bash create_repos.sh [--path /chemin] [--yes] [nom_repo]
#
# Les dépôts sont créés en PRIVÉ (sauf REPO_PRIVATE=false dans .env).
# Les dossiers listés dans EXCLUDE_REPOS (.env) sont ignorés.
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps curl git jq flock
detect_env
acquire_lock

DEFAULT_BRANCH="main"
FILTER_REPO=""
ASSUME_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) BASE_PATH="$2"; shift 2 ;;
        --yes|-y) ASSUME_YES=true; shift ;;
        --*) echo "Option inconnue : $1"; exit 1 ;;
        *) FILTER_REPO="$1"; shift ;;
    esac
done

if [ ! -d "$BASE_PATH" ]; then
    echo "❌ Le chemin $BASE_PATH n'existe pas."
    exit 1
fi

# Liste des dossiers qui seront traités
targets=()
for dir in "$BASE_PATH"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    if [ -n "$FILTER_REPO" ]; then
        [ "$name" != "$FILTER_REPO" ] && continue
    else
        is_excluded_repo "$name" && continue
    fi
    targets+=("$name")
done

if [ ${#targets[@]} -eq 0 ]; then
    echo "⚠️  Aucun dossier à traiter dans $BASE_PATH"
    exit 0
fi

visibility="PRIVÉS"
[ "$REPO_PRIVATE" = "false" ] && visibility="⚠️  PUBLICS"

echo "=== Création/initialisation des dépôts dans : $BASE_PATH ==="
echo "Dossiers concernés (${#targets[@]}) :"
printf '  - %s\n' "${targets[@]}"
echo "Les nouveaux dépôts GitHub seront $visibility."
[ -n "$EXCLUDE_REPOS" ] && echo "Exclusions (.env) : $EXCLUDE_REPOS"

if ! $ASSUME_YES; then
    read -rp "Continuer ? (oui/non) : " confirm
    [ "$confirm" != "oui" ] && echo "Annulé." && exit 0
fi

# Initialise un dépôt Git local et le lie à GitHub (appelée dans le dossier)
initialize_local_repo() {
    local repo_name
    repo_name=$(basename "$PWD")

    if [ -d ".git" ]; then
        echo "  ℹ️  Dépôt Git déjà initialisé."
        set_remote_ssh "$repo_name"
        return 0
    fi

    echo "  → git init..."
    git init -q
    git symbolic-ref HEAD "refs/heads/$DEFAULT_BRANCH"

    # Git LFS pour les archives
    if command -v git-lfs &>/dev/null; then
        git lfs install --local >/dev/null
        grep -q '\*.zip filter=lfs' .gitattributes 2>/dev/null || git lfs track "*.zip" >/dev/null
    fi

    # .gitignore de base (secrets courants inclus)
    if [ ! -f ".gitignore" ]; then
        cat > .gitignore <<'GITIGNORE'
# Logs & temporaires
*.log
*.tmp
.DS_Store

# Dépendances
node_modules/
vendor/

# Secrets / configuration locale
.env
.env.*
!.env.example
*.pem
*.key
GITIGNORE
    fi

    add_files_to_git
    if git diff --cached --quiet; then
        touch .gitkeep
        git add .gitkeep
    fi

    if ! git commit -q -m "Initial commit — $(date '+%Y-%m-%d %H:%M')"; then
        echo "  ❌ Commit impossible (git config --global user.name / user.email ?)."
        return 1
    fi

    set_remote_ssh "$repo_name"

    echo "  → Push initial vers GitHub..."
    if git push -q -u origin "$DEFAULT_BRANCH"; then
        echo "  ✅ $repo_name initialisé et pushé."
    else
        echo "  ❌ Erreur lors du push (dépôt GitHub non vide ? clé SSH ? → bash install_github.sh)."
        return 1
    fi
}

success=0
errors=0

for repo_name in "${targets[@]}"; do
    echo ""
    echo "📁 $repo_name"

    if github_repo_exists "$repo_name"; then
        echo "  ℹ️  Dépôt déjà présent sur GitHub."
    else
        github_create_repo "$repo_name" || { errors=$((errors + 1)); continue; }
    fi

    if (cd "$BASE_PATH/$repo_name" && initialize_local_repo); then
        success=$((success + 1))
    else
        errors=$((errors + 1))
    fi
done

echo ""
echo "=== create_repos.sh terminé : $success réussi(s), $errors erreur(s) ==="
