#!/bin/bash
# =============================================================
# sync_initial.sh — Synchronisation initiale sécurisée
#
# À utiliser UNE SEULE FOIS pour remettre de l'ordre quand
# l'état est incertain (WSL + OVH + GitHub pas alignés).
#
# Stratégie par dépôt :
#   - Modifs non commitées   → commit
#   - Local en avance        → push vers GitHub
#   - GitHub en avance       → mise à jour locale (avance rapide)
#   - Divergence             → sauvegarde + rebase sur GitHub + push
#                              (si conflit : rebase annulé, sauvegarde conservée)
#   - Absent de GitHub       → crée le dépôt (privé) et push
#   - Absent en local        → clone depuis GitHub
#
# Les sauvegardes vont dans BACKUP_PATH (défaut ~/git_backups),
# jamais dans le webroot.
#
# Usage :
#   bash sync_initial.sh              # tous les dépôts
#   bash sync_initial.sh mon_repo     # un seul dépôt
#   bash sync_initial.sh --dry-run    # simulation (seul un git fetch est fait)
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps git curl jq flock
detect_env
acquire_lock

DEFAULT_BRANCH="main"
DRY_RUN=false
FILTER_REPO=""
BACKUP_DIR="$BACKUP_PATH/sync_initial_$(date +%Y%m%d_%H%M%S)"

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --*) echo "Option inconnue : $arg"; exit 1 ;;
        *) FILTER_REPO="$arg" ;;
    esac
done

echo "======================================================"
echo "  SYNCHRONISATION INITIALE — $ENV_LABEL"
echo "  Chemin : $BASE_PATH"
$DRY_RUN && echo "  ⚠️  MODE DRY-RUN (aucune modification des dépôts)"
[ -n "$FILTER_REPO" ] && echo "  Dépôt : $FILTER_REPO"
echo "======================================================"
echo ""

if [ ! -d "$BASE_PATH" ]; then
    echo "❌ Le chemin $BASE_PATH n'existe pas."
    exit 1
fi

if ! $DRY_RUN; then
    echo "Ce script va analyser et synchroniser vos dépôts."
    echo "En cas de divergence, une sauvegarde sera faite dans :"
    echo "  $BACKUP_DIR"
    [ "$REPO_PRIVATE" = "false" ] && echo "⚠️  Les dépôts créés sur GitHub seront PUBLICS (REPO_PRIVATE=false)."
    echo ""
    read -rp "Continuer ? (oui/non) : " confirm
    [ "$confirm" != "oui" ] && echo "Annulé." && exit 0
    echo ""
fi

echo "Récupération des dépôts GitHub..."
github_repos=$(github_list_repos | sort)
if [ -z "$github_repos" ]; then
    echo "❌ Impossible de récupérer les dépôts GitHub (token ?)."
    echo "   (Si vous n'avez encore aucun dépôt GitHub, utilisez create_repos.sh.)"
    exit 1
fi

on_github() { echo "$github_repos" | grep -qx "$1"; }

# Sauvegarde du dossier courant avant opération risquée
backup_repo() {
    local repo_name; repo_name=$(basename "$PWD")
    mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_PATH" "$BACKUP_DIR" 2>/dev/null
    if cp -a "$PWD" "$BACKUP_DIR/$repo_name"; then
        echo "  💾 Sauvegarde : $BACKUP_DIR/$repo_name"
    else
        echo "  ❌ Sauvegarde impossible — opération annulée par sécurité."
        return 1
    fi
}

commit_all() {
    local msg="$1"
    add_files_to_git
    git diff --cached --quiet && return 0
    git commit -q -m "$msg" || { echo "  ❌ Commit impossible (git config user.name / user.email ?)."; return 1; }
}

# ── Cas 1 : dossier sans .git ────────────────────────────────
handle_no_git() {
    local repo_name="$1" target_branch

    if on_github "$repo_name"; then
        echo "  → Dossier sans Git, dépôt existant sur GitHub → init + rattachement"
        $DRY_RUN && return 0

        target_branch=$(remote_default_branch "git@github.com:$GITHUB_USER/$repo_name.git" "$DEFAULT_BRANCH")
        backup_repo || return 1
        git init -q
        git symbolic-ref HEAD "refs/heads/$target_branch"
        set_remote_ssh "$repo_name"
        git fetch origin --quiet || { echo "  ❌ fetch impossible."; return 1; }

        commit_all "Contenu local initial — sync_initial.sh" || return 1

        if remote_branch_exists "$target_branch"; then
            echo "  → GitHub contient déjà des commits → fusion avec le contenu local..."
            if ! git rev-parse -q --verify HEAD >/dev/null; then
                # Aucun fichier local : on prend simplement GitHub
                git reset -q --hard "origin/$target_branch"
            elif ! out=$(git merge "origin/$target_branch" --allow-unrelated-histories \
                    -m "Merge initial local + GitHub" 2>&1); then
                git merge --abort 2>/dev/null
                echo "  ❌ Conflits entre le local et GitHub — fusion annulée."
                echo "$out" | head -15 | sed 's/^/     /'
                echo "     Sauvegarde : $BACKUP_DIR/$repo_name"
                return 1
            fi
        elif ! git rev-parse -q --verify HEAD >/dev/null; then
            touch .gitkeep && git add .gitkeep && git commit -q -m "Initial commit — sync_initial.sh"
        fi

        git push -q -u origin "$target_branch" && echo "  ✅ Synchronisé." || { echo "  ❌ Push échoué."; return 1; }
    else
        echo "  → Dossier sans Git, absent de GitHub → init + création GitHub + push"
        $DRY_RUN && return 0

        github_create_repo "$repo_name" || return 1
        git init -q
        git symbolic-ref HEAD "refs/heads/$DEFAULT_BRANCH"
        set_remote_ssh "$repo_name"
        commit_all "Initial commit — sync_initial.sh" || return 1
        if ! git rev-parse -q --verify HEAD >/dev/null; then
            touch .gitkeep && git add .gitkeep && git commit -q -m "Initial commit — sync_initial.sh"
        fi
        git push -q -u origin "$DEFAULT_BRANCH" && echo "  ✅ Dépôt créé et pushé." || { echo "  ❌ Push échoué."; return 1; }
    fi
}

# ── Cas 2 : dépôt Git existant ───────────────────────────────
handle_git() {
    local repo_name="$1" branch ahead behind modified

    if rebase_in_progress; then
        echo "  ⚠️  Rebase/merge en cours — résolvez-le d'abord (git status)."
        return 1
    fi
    if ! git symbolic-ref -q HEAD >/dev/null; then
        echo "  ⚠️  HEAD détaché — repassez sur une branche."
        return 1
    fi
    branch=$(current_branch "$DEFAULT_BRANCH")

    if ! git remote get-url origin &>/dev/null; then
        if on_github "$repo_name"; then
            echo "  → Remote manquant : rattachement au dépôt GitHub existant"
            $DRY_RUN || set_remote_ssh "$repo_name"
        else
            echo "  → Remote manquant et absent de GitHub : création + rattachement"
            if ! $DRY_RUN; then
                github_create_repo "$repo_name" || return 1
                set_remote_ssh "$repo_name"
            fi
        fi
    fi

    # Le fetch ne touche pas aux fichiers : on le fait aussi en dry-run
    # pour que l'analyse soit juste
    git remote get-url origin &>/dev/null && git fetch origin --quiet 2>/dev/null

    ahead=$(commits_ahead "$branch")
    behind=$(commits_behind "$branch")
    modified=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    remote_branch_exists "$branch" || echo "  ℹ️  origin/$branch n'existe pas encore sur GitHub"
    echo "  État : $ahead en avance, $behind en retard, $modified fichier(s) non commité(s)"

    if [ "$modified" -gt 0 ]; then
        echo "  → Commit des modifications locales en attente"
        if ! $DRY_RUN; then
            commit_all "Commit pré-sync — sync_initial.sh $(date '+%Y-%m-%d %H:%M')" || return 1
            ahead=$(commits_ahead "$branch")
        fi
    fi

    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
        echo "  ✅ Déjà synchronisé."

    elif [ "$behind" -eq 0 ]; then
        echo "  → Local en avance de $ahead commit(s) → push"
        $DRY_RUN && return 0
        git push -q -u origin "$branch" && echo "  ✅ Push réussi." || { echo "  ❌ Push échoué."; return 1; }

    elif [ "$ahead" -eq 0 ]; then
        echo "  → GitHub en avance de $behind commit(s) → mise à jour locale"
        $DRY_RUN && return 0
        git merge -q --ff-only "origin/$branch" && echo "  ✅ Mis à jour." \
            || { echo "  ❌ Mise à jour impossible (fichiers locaux en conflit ?)."; return 1; }

    else
        echo "  ⚡ DIVERGENCE ($ahead local / $behind distant) → sauvegarde + rebase"
        $DRY_RUN && return 0
        backup_repo || return 1
        if git rebase -q --autostash "origin/$branch" 2>/dev/null; then
            git push -q -u origin "$branch" && echo "  ✅ Rebase + push réussi." || { echo "  ❌ Push échoué."; return 1; }
        else
            git rebase --abort 2>/dev/null
            echo "  ❌ Rebase impossible (conflits) — annulé, dépôt inchangé."
            echo "     cd $PWD && git log --oneline --graph --all"
            echo "     Sauvegarde : $BACKUP_DIR/$repo_name"
            return 1
        fi
    fi
}

echo "── Analyse des dossiers locaux ────────────────────────"
echo ""

errors=0
for dir in "$BASE_PATH"/*/; do
    [ -d "$dir" ] || continue
    repo_name=$(basename "$dir")
    if [ -n "$FILTER_REPO" ]; then
        [ "$repo_name" != "$FILTER_REPO" ] && continue
    else
        is_excluded_repo "$repo_name" && continue
    fi

    echo "📁 $repo_name"
    if [ -d "$dir/.git" ]; then
        (cd "$dir" && handle_git "$repo_name") || errors=$((errors + 1))
    else
        (cd "$dir" && handle_no_git "$repo_name") || errors=$((errors + 1))
    fi
    echo ""
done

echo "── Dépôts GitHub absents en local ─────────────────────"
echo ""

cloned=0
while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    if [ -n "$FILTER_REPO" ]; then
        [ "$repo" != "$FILTER_REPO" ] && continue
    else
        is_excluded_repo "$repo" && continue
    fi
    [ -e "$BASE_PATH/$repo" ] && continue

    echo "📥 $repo → clonage"
    if $DRY_RUN; then
        echo "  [dry-run] git clone git@github.com:$GITHUB_USER/$repo.git $BASE_PATH/$repo"
    elif git clone -q "git@github.com:$GITHUB_USER/$repo.git" "$BASE_PATH/$repo"; then
        echo "  ✅ Cloné dans $BASE_PATH/$repo"
        cloned=$((cloned + 1))
    else
        echo "  ❌ Erreur clonage"
        errors=$((errors + 1))
    fi
done <<< "$github_repos"

[ "$cloned" -eq 0 ] && ! $DRY_RUN && echo "  Aucun dépôt cloné."
echo ""
echo "======================================================"
echo "  Synchronisation initiale terminée — $errors problème(s)."
$DRY_RUN && echo "  (Dry-run — relancez sans --dry-run pour appliquer)"
echo "======================================================"
echo ""
echo "Prochaine étape : 'bash sync_bidirectionnel.sh' au quotidien."
