# Gestion_Git

Scripts Bash pour synchroniser automatiquement vos dépôts Git entre **WSL (local)**, votre **serveur OVH** et **GitHub**.

---

## Architecture

```
WSL (local)  ←──────────────────→  GitHub  ←──────────────────→  OVH (serveur)
              push/pull via SSH               push/pull via SSH
```

GitHub est toujours le point central :
- Modification en local (WSL) → push vers GitHub → récupération sur OVH
- Modification sur OVH → push vers GitHub → récupération en local
- `sync_bidirectionnel.sh` fait tout ça en un seul appel

---

## Installation

### 1. Prérequis

```bash
sudo apt update && sudo apt install -y git curl jq git-lfs util-linux
```

(`util-linux` fournit `flock`, utilisé pour empêcher deux synchros simultanées.)

Identité Git, sur chaque machine :

```bash
git config --global user.name  "Laurent"
git config --global user.email "vous@exemple.fr"
```

### 2. Configurer le fichier `.env`

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Variables principales : `GITHUB_TOKEN`, `GITHUB_USER`, `OVH_BASE_PATH`, `LOCAL_BASE_PATH`.
Variables optionnelles : `REPO_PRIVATE`, `EXCLUDE_REPOS`, `BACKUP_PATH`, `FILE_SIZE_LIMIT` (voir les commentaires dans `.env.example`).

Token (classic) à générer sur https://github.com/settings/tokens avec les scopes :

| Scope | Utilisé par |
|-------|-------------|
| `repo` | tous les scripts |
| `admin:public_key` | `install_github.sh` |
| `delete_repo` | `delete_repos.sh` uniquement — à omettre si vous ne l'utilisez pas |

> ⚠️ Ne commitez jamais `.env`. Sur un serveur exposé, préférez un token sans `delete_repo`.

### 3. Configurer SSH (une fois par machine)

```bash
bash install_github.sh
```

Génère une clé `ed25519`, l'enregistre sur GitHub et ajoute `github.com` aux `known_hosts` **après vérification de l'empreinte officielle**. À faire sur WSL et sur OVH séparément.

### 4. Rendre les scripts exécutables

```bash
chmod +x *.sh
```

---

## Scripts disponibles

| Script | Description |
|--------|-------------|
| `install_github.sh` | Configure SSH et enregistre la clé sur GitHub |
| `create_repos.sh` | Crée les dépôts GitHub (privés) + initialise les dépôts locaux |
| `clone_repos.sh` | Clone tous vos dépôts GitHub en local |
| `sync_initial.sh` | **Une seule fois** : remet d'aplomb un état incertain (supporte `--dry-run`) |
| `sync_bidirectionnel.sh` | **Script principal au quotidien** : commit, rebase, push, récupération |
| `push_repos.sh` | Commit les changements locaux et push vers GitHub |
| `pull_repos.sh` | Récupère GitHub (avance rapide uniquement) |
| `diagnostic.sh` | État de chaque dépôt : en avance, en retard, divergent, bloqué |
| `delete_repos.sh` | Supprime des dépôts GitHub (avec confirmation) |
| `remove_git.sh` | Supprime les dossiers `.git` locaux |
| `lib_common.sh` | Bibliothèque partagée (ne pas appeler directement) |

Les scripts qui modifient les dépôts acceptent un nom de dépôt en argument pour n'en traiter qu'un seul.

---

## Utilisation courante

### Première mise en place

```bash
# Sur WSL et sur OVH (séparément) :
bash install_github.sh

# Voir ce qui va se passer, sans rien modifier :
bash diagnostic.sh
bash sync_initial.sh --dry-run

# Appliquer :
bash sync_initial.sh
```

Alternatives : `create_repos.sh` (partir des dossiers existants) ou `clone_repos.sh` (partir de GitHub).

### Au quotidien

```bash
bash sync_bidirectionnel.sh              # tous les dépôts
bash sync_bidirectionnel.sh mon_projet   # un seul dépôt
bash sync_bidirectionnel.sh --pull-only  # seulement récupérer
bash sync_bidirectionnel.sh --push-only  # seulement envoyer
```

### Opérations manuelles

```bash
bash push_repos.sh --message "Mon message"   # push de tous les dépôts
bash pull_repos.sh mon_projet                # récupérer un dépôt
bash delete_repos.sh mon_repo                # supprimer un dépôt GitHub
bash delete_repos.sh                         # supprimer TOUS les dépôts (⚠️)
```

---

## Comportement en cas de problème

- **Suppressions** : un fichier supprimé en local est bien supprimé sur GitHub puis sur l'autre machine.
- **Push raté** (réseau…) : les commits en attente sont renvoyés automatiquement au passage suivant.
- **Conflit** : le rebase est **annulé automatiquement**, le dépôt reste propre et est signalé en erreur. Les autres dépôts continuent.
- **Rebase/merge laissé en cours à la main** : le dépôt est ignoré tant que ce n'est pas réglé.
- **Dépôt Git dans un sous-dossier** : exclu automatiquement du dépôt parent (à synchroniser comme un dépôt à part).
- **Fichiers > 100 Mo** : ajoutés au `.gitignore` du dépôt et jamais envoyés.
- **Dossiers exclus** : cachés, `_backups_*`, et tout motif de `EXCLUDE_REPOS`.

---

## Automatisation avec cron (OVH)

```bash
crontab -e
```

```cron
0 * * * * cd /home/ubuntu/Gestion_Git && bash sync_bidirectionnel.sh >> /home/ubuntu/git_sync.log 2>&1
```

Le log est dans le dossier de l'utilisateur (`/var/log` n'est pas accessible en écriture pour `ubuntu`). Si une synchro dure plus d'une heure, la suivante s'arrête d'elle-même grâce au verrou.

> ℹ️ Si des fichiers de `/var/www/html` appartiennent à `www-data`, l'utilisateur qui lance le cron doit pouvoir les lire et écrire (groupe `www-data`, par exemple).

---

## Sécurité

- Les dépôts sont créés **privés** par défaut (`REPO_PRIVATE=true`).
- Le `.gitignore` généré exclut `.env`, `.env.*`, `*.pem`, `*.key`. Vérifiez qu'aucun autre fichier de config avec mots de passe (`config.php`, `wp-config.php`…) n'est versionné.
- Les dossiers `.git` sont dans le webroot : bloquez-les côté Apache, par exemple dans la config du vhost :
  ```apache
  <DirectoryMatch "/\.git">
      Require all denied
  </DirectoryMatch>
  ```

---

## Dépannage

**Erreur SSH « Permission denied »**
```bash
bash install_github.sh
ssh -T git@github.com
```

**Dépôt signalé en conflit**
```bash
cd /var/www/html/mon_repo
git pull --rebase origin main   # résoudre les conflits, puis :
git rebase --continue           # ou git rebase --abort
```

**Token GitHub invalide / droits insuffisants**
Générez un nouveau token (scopes ci-dessus) et mettez à jour `.env`.

---

## Licence

Distribué sous licence [MIT](LICENSE) — © 2026 Laurent Lebarbier. Utilisation, modification et
redistribution libres ; les scripts sont fournis « tels quels », sans garantie : testez-les
d'abord sur un dépôt sans importance (`sync_initial.sh` et `delete_repos.sh` modifient
GitHub).

> 🔒 Ne commitez jamais votre `.env` : il contient votre token GitHub (déjà exclu par le
> `.gitignore`). Un token publié par erreur doit être **révoqué immédiatement** sur
> GitHub → Settings → Developer settings → Personal access tokens.
