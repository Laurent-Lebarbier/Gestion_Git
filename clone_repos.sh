#!/bin/bash
[ -f .env ] && export $(grep -v '^#' .env | xargs)

# Configuration
GITHUB_USER="Laurent-Lebarbier"  # Remplacez par votre nom d'utilisateur GitHub
GITHUB_TOKEN="${GITHUB_TOKEN:?Veuillez définir la variable d environnement GITHUB_TOKEN}"

CLONE_DIR="/var/www/html"  # Répertoire où les dépôts seront clonés

# Vérifie si le répertoire cible existe, sinon le créer
if [ ! -d "$CLONE_DIR" ]; then
    echo "Création du répertoire $CLONE_DIR..."
    mkdir -p "$CLONE_DIR"
fi

# Fonction pour cloner un dépôt
clone_repo() {
    local repo_name=$1
    local repo_url="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${repo_name}.git"
    local repo_path="${CLONE_DIR}/${repo_name}"

    if [ -d "$repo_path" ]; then
        echo "Le dépôt $repo_name existe déjà dans $CLONE_DIR. Ignoré."
    else
        echo "Clonage du dépôt $repo_name dans $CLONE_DIR..."
        git clone "$repo_url" "$repo_path"
        if [ $? -eq 0 ]; then
            echo "Dépôt $repo_name cloné avec succès."
        else
            echo "Échec du clonage du dépôt $repo_name."
        fi
    fi
}

# Récupération de la liste des dépôts via l'API GitHub
echo "Récupération de la liste des dépôts pour l'utilisateur $GITHUB_USER..."
repos=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/user/repos?per_page=100" | jq -r '.[].name')

# Vérifie si `jq` est installé
if [ -z "$repos" ]; then
    echo "Erreur : Assurez-vous que l'outil 'jq' est installé pour parser les résultats JSON."
    exit 1
fi

# Parcours de chaque dépôt et clonage
for repo_name in $repos; do
    clone_repo "$repo_name"
done

echo "Toutes les opérations sont terminées."