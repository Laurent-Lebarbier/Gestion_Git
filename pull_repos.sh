#!/bin/bash

# Configuration
BASE_PATH="/var/www/html"
GITHUB_USER="Laurent-Lebarbier"
GITHUB_TOKEN="${GITHUB_TOKEN:?Veuillez définir la variable d'environnement GITHUB_TOKEN}"

# Vérifie si le dossier de base existe
if [ ! -d "$BASE_PATH" ]; then
    echo "Le dossier $BASE_PATH n'existe pas."
    exit 1
fi

# Se déplace dans le dossier de base
cd "$BASE_PATH" || {
    echo "Impossible de se déplacer dans $BASE_PATH."
    exit 1
}

# Parcourt chaque sous-dossier
for depot in */; do
    echo "Traitement du dépôt : $depot"
    cd "$depot" || {
        echo "Impossible de se déplacer dans $depot."
        continue
    }

    # Vérifie si c'est un dépôt Git
    if [ -d ".git" ]; then
        echo "Exécution de 'git pull' dans $depot..."
        git pull
        if [ $? -ne 0 ]; then
            echo "Erreur lors du 'git pull' dans $depot."
        fi
    else
        echo "$depot n'est pas un dépôt Git."
    fi

    # Retourne au dossier parent
    cd ..
done

echo "Mise à jour terminée pour tous les dépôts."
