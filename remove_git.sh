#!/bin/bash

# Chemin du répertoire contenant les dépôts locaux
BASE_DIR="/var/www/html"

# Parcourt tous les sous-répertoires de BASE_DIR
for repo in "$BASE_DIR"/*; do
    # Vérifie si le dossier contient un .git
    if [ -d "$repo/.git" ]; then
        echo "Suppression du dossier .git dans : $repo"
        rm -rf "$repo/.git"
    else
        echo "Pas de dossier .git trouvé dans : $repo"
    fi
done

echo "Opération terminée."