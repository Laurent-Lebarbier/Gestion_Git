# Changelog

## 2026-09-22 (b) — Dépôts imbriqués
- Un sous-dossier contenant son propre `.git` n'est plus enregistré comme lien vide
  (« embedded git repository ») : il est ajouté au `.gitignore` du dépôt parent.
- Les liens déjà commités par erreur sont retirés automatiquement de l'index au
  prochain `sync_bidirectionnel.sh` / `push_repos.sh` (les dossiers ne sont pas touchés).

## 2026-09-22 — Corrections

### Bugs corrigés
- **Suppressions jamais propagées** : `add_files_to_git` utilise désormais `git add -A` (les fichiers supprimés sont stagés). Plus d'un `git add` par fichier : beaucoup plus rapide.
- **Commits non pushés bloqués** : `push_repos.sh` et `sync_bidirectionnel.sh` poussent tout commit en attente, même sans nouvelle modification.
- **Rebase raté laissé en cours** : le rebase est annulé automatiquement en cas de conflit ; les dépôts avec un rebase/merge en cours ou un HEAD détaché sont ignorés et signalés.
- **Dépôt GitHub vide vu comme « synchronisé »** (`sync_initial.sh`, `diagnostic.sh`) : si `origin/<branche>` n'existe pas, tous les commits locaux sont comptés comme à pousser.
- **`install_github.sh` échouait au 2e lancement** : comparaison de la clé sans le commentaire `user@host` ; JSON construit avec `jq`.
- **`create_repos.sh --path`** : l'option est enfin lue correctement.
- **`git pull` implicite** remplacé par `fetch` + avance rapide (`--ff-only`) : plus d'erreur « divergent branches » ni de merge surprise.
- **Pagination** au-delà de 100 dépôts dans tous les scripts.
- Dépôt local sans commit : récupération correcte depuis GitHub.

### Sécurité
- Dépôts créés **privés** par défaut (`REPO_PRIVATE`).
- `EXCLUDE_REPOS` pour ne jamais synchroniser certains dossiers ; `.*` et `_backups_*` toujours exclus.
- Sauvegardes de `sync_initial.sh` déplacées **hors du webroot** (`BACKUP_PATH`, défaut `~/git_backups`).
- Avertissement si `.env` n'est pas en `chmod 600`.
- Empreinte de `github.com` vérifiée avant ajout aux `known_hosts`.
- `.gitignore` généré : ajout de `.env.*`, `*.pem`, `*.key`.

### Divers
- Verrou `flock` : deux synchros ne peuvent plus tourner en même temps (cron + manuel).
- Chaque dépôt est traité dans un sous-shell : une erreur sur l'un n'affecte pas les autres.
- Fonctions communes regroupées dans `lib_common.sh` (`detect_env`, `commit_and_push`, `pull_ff_only`…).
- `create_repos.sh` affiche la liste des dossiers concernés et demande confirmation (`--yes` pour passer).
- Code de sortie ≠ 0 si au moins un dépôt est en erreur (utile pour le cron).
- README : scopes du token, `sync_initial.sh` et `diagnostic.sh` documentés, cron corrigé.
