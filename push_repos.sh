#!/bin/bash
# Charger les variables d'environnement depuis .env si présent
[ -f .env ] && export $(grep -v '^#' .env | xargs)

# Configuration
BASE_PATH="/var/www/html"
GITHUB_USER="Laurent-Lebarbier"  # Remplacez par votre nom d'utilisateur GitHub
GITHUB_TOKEN="${GITHUB_TOKEN:?Veuillez définir la variable d environnement GITHUB_TOKEN}"
DEFAULT_BRANCH="main"  # Branche par défaut
FILE_SIZE_LIMIT=104857600  # Limite de taille de fichier en octets (100 MB)

# Fonction pour ajouter des fichiers à Git en vérifiant la taille
add_files_to_git() {
    for item in *; do
        if [ -f "$item" ]; then
            file_size=$(stat -c%s "$item")
            if [ "$file_size" -gt "$FILE_SIZE_LIMIT" ]; then
                echo "Le fichier $item dépasse la limite de taille de GitHub (100 MB) et sera ignoré."
            else
                git add "$item"
            fi
        elif [ -d "$item" ]; then
            git add "$item"
        fi
    done
}

# Fonction pour synchroniser les modifications avec GitHub
sync_with_github() {
    local dir_path=$1

    cd "$dir_path" || exit 1

    echo "Synchronisation des modifications pour $(basename "$dir_path")..."

    # Exclure les workflows
    if [ -d ".github" ]; then
        echo "Exclusion des workflows .github pour éviter les erreurs de permission..."
        git rm -r --cached .github 2>/dev/null
    fi

    git lfs install
    git lfs track "*.zip"

    add_files_to_git
    if git commit -m "Mise à jour automatique"; then
        git pull origin "$DEFAULT_BRANCH" --rebase
        git push -u origin "$DEFAULT_BRANCH"

        if [ $? -eq 0 ]; then
            echo "Synchronisation réussie pour $(basename "$dir_path")."
        else
            echo "Erreur lors de la synchronisation pour $(basename "$dir_path")."
        fi
    else
        echo "Aucune modification à synchroniser pour $(basename "$dir_path")."
        # Forcer le push si le dépôt est vide sur GitHub
        git push -u origin "$DEFAULT_BRANCH"
    fi
}

# Parcours des répertoires dans BASE_PATH
for dir in "$BASE_PATH"/*; do
    if [ -d "$dir" ]; then
        # Synchroniser le dépôt local avec GitHub
        sync_with_github "$dir"
    fi
done

# Fin du script
echo "Script push.sh terminé."