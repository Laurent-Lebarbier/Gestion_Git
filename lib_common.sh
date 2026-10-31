#!/bin/bash
# =============================================================
# lib_common.sh — Fonctions partagées par tous les scripts Git
# Source ce fichier depuis les autres scripts :
#   source "$(dirname "$0")/lib_common.sh"
# Ne pas exécuter directement.
# =============================================================

# ── Chargement de la configuration ───────────────────────────

# Charge le .env situé dans le même dossier que le script appelant
load_env() {
    local script_dir env_file perms
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    env_file="$script_dir/.env"

    if [ ! -f "$env_file" ]; then
        echo "❌ Fichier .env introuvable dans $script_dir"
        echo "   Copiez .env.example en .env et remplissez vos valeurs."
        exit 1
    fi

    # Le .env contient un token GitHub : il ne doit être lisible que par vous
    perms=$(stat -c %a "$env_file" 2>/dev/null)
    if [ -n "$perms" ] && [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
        echo "⚠️  $env_file a les permissions $perms — recommandé : chmod 600 $env_file"
    fi

    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a

    : "${GITHUB_TOKEN:?La variable GITHUB_TOKEN est manquante dans .env}"
    : "${GITHUB_USER:?La variable GITHUB_USER est manquante dans .env}"

    # Valeurs par défaut
    FILE_SIZE_LIMIT="${FILE_SIZE_LIMIT:-104857600}"      # 100 Mo
    REPO_PRIVATE="${REPO_PRIVATE:-true}"                 # dépôts privés par défaut
    BACKUP_PATH="${BACKUP_PATH:-$HOME/git_backups}"      # HORS du webroot
    EXCLUDE_REPOS="${EXCLUDE_REPOS:-}"
}

# Détermine BASE_PATH et ENV_LABEL selon la machine (WSL ou OVH)
detect_env() {
    if grep -qi microsoft /proc/version 2>/dev/null; then
        BASE_PATH="${LOCAL_BASE_PATH:-$HOME/projets}"
        ENV_LABEL="WSL (local)"
    else
        BASE_PATH="${OVH_BASE_PATH:-/var/www/html}"
        ENV_LABEL="OVH (serveur)"
    fi
}

# Vérifie la présence des commandes nécessaires
check_deps() {
    local dep
    for dep in "$@"; do
        if ! command -v "$dep" &>/dev/null; then
            echo "❌ Dépendance manquante : $dep"
            echo "   Installez-la avec : sudo apt install $dep"
            exit 1
        fi
    done
}

# Empêche deux synchronisations de tourner en même temps (cron + manuel)
acquire_lock() {
    local lock_file="${XDG_RUNTIME_DIR:-/tmp}/gestion_git_$(id -u).lock"
    exec 9>"$lock_file"
    if ! flock -n 9; then
        echo "⏳ Une autre opération Gestion_Git est déjà en cours, abandon."
        exit 0
    fi
}

# Retourne 0 si ce dossier doit être ignoré par les scripts
# (dossiers cachés, anciennes sauvegardes, motifs de EXCLUDE_REPOS)
is_excluded_repo() {
    local name="$1" pattern
    local -a patterns
    case "$name" in
        .*|_backups_*) return 0 ;;
    esac
    read -ra patterns <<< "$EXCLUDE_REPOS"
    for pattern in "${patterns[@]}"; do
        # shellcheck disable=SC2254
        case "$name" in $pattern) return 0 ;; esac
    done
    return 1
}

# ── API GitHub ───────────────────────────────────────────────

github_api() {
    local method="$1" endpoint="$2" data="${3:-}"
    local args=(
        -s
        -X "$method"
        -H "Authorization: Bearer $GITHUB_TOKEN"
        -H "Accept: application/vnd.github+json"
        -H "X-GitHub-Api-Version: 2022-11-28"
    )
    if [ -n "$data" ]; then
        args+=(-H "Content-Type: application/json" -d "$data")
    fi
    curl "${args[@]}" "https://api.github.com${endpoint}"
}

# Liste TOUS les dépôts de l'utilisateur (pagination gérée), un par ligne
github_list_repos() {
    local page=1 batch
    while :; do
        batch=$(github_api GET "/user/repos?per_page=100&page=$page&type=owner" \
            | jq -r 'if type == "array" then .[].name else empty end')
        [ -z "$batch" ] && break
        echo "$batch"
        page=$((page + 1))
    done
}

# Vérifie si un dépôt GitHub existe (0 = oui, 1 = non)
github_repo_exists() {
    local repo_name="$1" http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$GITHUB_USER/$repo_name")
    [ "$http_code" -eq 200 ]
}

# Crée un dépôt GitHub (privé sauf si REPO_PRIVATE=false dans .env)
github_create_repo() {
    local repo_name="$1" private=true payload response
    [ "$REPO_PRIVATE" = "false" ] && private=false

    payload=$(jq -nc --arg n "$repo_name" --arg d "Dépôt pour $repo_name" --argjson p "$private" \
        '{name: $n, description: $d, private: $p, auto_init: false}')
    response=$(github_api POST "/user/repos" "$payload")

    if echo "$response" | jq -e '.id' &>/dev/null; then
        if $private; then
            echo "  ✅ Dépôt GitHub créé (privé) : $repo_name"
        else
            echo "  ✅ Dépôt GitHub créé (PUBLIC) : $repo_name"
        fi
    elif echo "$response" | grep -q "already exists"; then
        echo "  ℹ️  Dépôt $repo_name déjà existant sur GitHub."
    else
        echo "  ❌ Erreur création $repo_name : $(echo "$response" | jq -r '.message // .')"
        return 1
    fi
}

# ── Git local ────────────────────────────────────────────────

# Configure le remote origin en SSH
set_remote_ssh() {
    local repo_name="$1"
    local remote_url="git@github.com:$GITHUB_USER/$repo_name.git"
    if git remote get-url origin &>/dev/null; then
        git remote set-url origin "$remote_url"
    else
        git remote add origin "$remote_url"
    fi
}

# Branche courante (fonctionne aussi sur un dépôt sans commit).
# Retombe sur $1 (défaut "main") si HEAD est détaché.
current_branch() {
    local fallback="${1:-main}" branch
    branch=$(git symbolic-ref --short -q HEAD 2>/dev/null)
    echo "${branch:-$fallback}"
}

# Branche par défaut d'un dépôt distant (avant clone), via HEAD symbolique
remote_default_branch() {
    local remote_url="$1" fallback="${2:-main}" branch
    branch=$(git ls-remote --symref "$remote_url" HEAD 2>/dev/null \
        | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2}')
    echo "${branch:-$fallback}"
}

# 0 si origin/<branche> existe (après fetch)
remote_branch_exists() {
    git rev-parse --verify -q "refs/remotes/origin/$1" >/dev/null
}

# Nombre de commits locaux absents de GitHub.
# Si la branche distante n'existe pas encore, TOUS les commits sont à pousser.
commits_ahead() {
    local branch="$1"
    if remote_branch_exists "$branch"; then
        git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0
    else
        git rev-list --count HEAD 2>/dev/null || echo 0
    fi
}

# Nombre de commits GitHub absents en local
commits_behind() {
    local branch="$1"
    if ! remote_branch_exists "$branch"; then
        echo 0
    elif git rev-parse -q --verify HEAD >/dev/null; then
        git rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0
    else
        # Dépôt local sans aucun commit : tout GitHub est à récupérer
        git rev-list --count "origin/$branch" 2>/dev/null || echo 0
    fi
}

# 0 si un rebase ou un merge est en cours dans le dépôt
rebase_in_progress() {
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] || [ -f "$git_dir/MERGE_HEAD" ]
}

# Vérifications communes avant de toucher un dépôt (à appeler dans le dossier)
check_repo_ready() {
    local repo_name="$1"
    if [ ! -d ".git" ]; then
        echo "  ⚠️  Pas un dépôt Git (lancez create_repos.sh ou clone_repos.sh)."
        return 1
    fi
    if rebase_in_progress; then
        echo "  ⚠️  Rebase ou merge en cours — terminez-le ou annulez-le d'abord :"
        echo "     cd $PWD && git status"
        return 1
    fi
    if ! git symbolic-ref -q HEAD >/dev/null; then
        echo "  ⚠️  HEAD détaché — repassez sur une branche (git switch main)."
        return 1
    fi
    if ! git remote get-url origin &>/dev/null; then
        set_remote_ssh "$repo_name"
        echo "  ℹ️  Remote SSH configuré : $(git remote get-url origin)"
    fi
}

# Dépôts Git imbriqués (un projet qui a son propre .git dans un sous-dossier) :
# on les exclut du dépôt parent via .gitignore, sinon Git n'enregistre qu'un
# lien vide ("embedded git repository") et leur contenu n'est jamais envoyé.
# Si un tel lien a déjà été commité, il est retiré de l'index.
exclude_nested_repos() {
    local g sub
    while IFS= read -r -d '' g; do
        sub="${g%/.git}"; sub="${sub#./}"
        if ! grep -qxF "/$sub/" .gitignore 2>/dev/null; then
            echo "  ⚠️  Dépôt Git imbriqué exclu : $sub (à synchroniser séparément)"
            printf '/%s/\n' "$sub" >> .gitignore
        fi
        # S'il a déjà été commité comme lien (gitlink), on le retire de l'index
        if git ls-files -s -- "$sub" 2>/dev/null | grep -q '^160000'; then
            echo "  → Retrait du lien '$sub' de l'index (le dossier n'est pas touché)"
            git rm -r -q --cached -- "$sub"
        fi
    done < <(find . \( -path ./.git -o -name node_modules -o -name vendor \) -prune \
                -o -name .git -print0 -prune)
}

# Stage TOUS les changements (ajouts, modifications ET suppressions),
# sauf les fichiers dépassant FILE_SIZE_LIMIT, qui sont ajoutés au .gitignore.
add_files_to_git() {
    local f size
    local -a large=()

    exclude_nested_repos

    # Repérer les gros fichiers AVANT le git add (évite de les écrire dans .git)
    while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
        if [ -n "$size" ] && [ "$size" -gt "$FILE_SIZE_LIMIT" ]; then
            echo "  ⚠️  Fichier ignoré (> $((FILE_SIZE_LIMIT / 1048576)) Mo) : $f"
            grep -qxF "/$f" .gitignore 2>/dev/null || printf '/%s\n' "$f" >> .gitignore
            large+=("$f")
        fi
    done < <(git ls-files -z --modified --others --exclude-standard)

    git add -A

    # Un gros fichier déjà suivi par Git n'est pas couvert par .gitignore :
    # on le retire du staging pour ne pas l'envoyer
    for f in "${large[@]}"; do
        git reset -q -- "$f" 2>/dev/null
    done
    return 0
}

# Récupère GitHub et rejoue les commits locaux par-dessus.
# En cas de conflit, le rebase est ANNULÉ : le dépôt reste dans un état propre.
rebase_on_remote() {
    local branch="$1" out
    if ! git fetch origin --quiet 2>/dev/null; then
        echo "  ❌ fetch impossible (réseau ou clé SSH ?)."
        return 1
    fi
    remote_branch_exists "$branch" || return 0   # dépôt distant vide : rien à rejouer
    if ! out=$(git rebase --autostash "origin/$branch" 2>&1); then
        git rebase --abort 2>/dev/null
        echo "  ❌ Conflit avec origin/$branch — rebase annulé, dépôt laissé intact."
        echo "$out" | head -15 | sed 's/^/     /'
        echo "     Résolution manuelle : cd $PWD && git pull --rebase origin $branch"
        return 1
    fi
}

# Commit les changements locaux, se cale sur GitHub puis pousse
# tous les commits en attente (y compris ceux d'un push précédent raté).
commit_and_push() {
    local branch="$1" msg="$2" ahead

    exclude_nested_repos

    if [ -n "$(git status --porcelain)" ]; then
        echo "  📤 Changements locaux détectés, staging..."
        add_files_to_git
        if ! git diff --cached --quiet; then
            if ! git commit -q -m "$msg"; then
                echo "  ❌ Commit impossible (git config user.name / user.email définis ?)."
                return 1
            fi
            echo "  → Commit créé."
        else
            echo "  ℹ️  Rien à commiter (uniquement des fichiers trop volumineux)."
        fi
    fi

    rebase_on_remote "$branch" || return 1

    ahead=$(commits_ahead "$branch")
    if [ "$ahead" -eq 0 ]; then
        echo "  ✅ Rien à pousser."
        return 0
    fi

    echo "  → Push de $ahead commit(s) vers origin/$branch..."
    if git push -q -u origin "$branch"; then
        echo "  ✅ Push réussi."
    else
        echo "  ❌ Push échoué."
        return 1
    fi
}

# Récupère GitHub en avance rapide uniquement (jamais de merge implicite)
pull_ff_only() {
    local branch="$1"
    if ! git fetch origin --quiet 2>/dev/null; then
        echo "  ❌ fetch impossible (réseau ou clé SSH ?)."
        return 1
    fi
    if ! remote_branch_exists "$branch"; then
        echo "  ℹ️  origin/$branch n'existe pas encore (dépôt distant vide)."
        return 0
    fi
    if [ "$(commits_behind "$branch")" -eq 0 ]; then
        echo "  ✅ Déjà à jour."
        return 0
    fi
    if git merge -q --ff-only "origin/$branch"; then
        echo "  ✅ Mis à jour depuis GitHub."
    else
        echo "  ❌ Impossible d'avancer (historiques divergents ou fichiers locaux en conflit)."
        echo "     Lancez sync_bidirectionnel.sh ou résolvez : cd $PWD && git status"
        return 1
    fi
}
