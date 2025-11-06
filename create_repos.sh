#!/bin/bash
# Charger les variables d'environnement depuis .env si présent
[ -f .env ] && export $(grep -v '^#' .env | xargs)

# Configuration
BASE_PATH="/var/www/html"
GITHUB_USER="Laurent-Lebarbier"  # Remplacez par votre nom d'utilisateur GitHub
GITHUB_TOKEN="${GITHUB_TOKEN:?Veuillez définir la variable d environnement GITHUB_TOKEN}"
DEFAULT_BRANCH="main"  # Branche par défaut
FILE_SIZE_LIMIT=104857600  # Limite de taille de fichier en octets (100 MB)

# Fonction pour créer un dépôt sur GitHub via l'API
create_github_repo() {
    local repo_name=$1
    local repo_desc="Dépôt pour $repo_name"

    echo "Création du dépôt $repo_name sur GitHub..."

    curl -u "$GITHUB_USER:$GITHUB_TOKEN" \
        -X POST https://api.github.com/user/repos \
        -d "{\"name\": \"$repo_name\", \"description\": \"$repo_desc\", \"private\": false}"

    if [ $? -eq 0 ]; then
        echo "Dépôt $repo_name créé avec succès."
    else
        echo "Erreur lors de la création du dépôt $repo_name."
        exit 1
    fi
}

# Fonction pour initialiser un dépôt Git local
initialize_local_repo() {
    local dir_path=$1

    cd "$dir_path" || exit 1

    if [ ! -d .git ]; then
        echo "Initialisation du dépôt Git local dans $dir_path..."
        git init
        git lfs install

        if ! grep -q '\*.zip filter=lfs' .gitattributes 2>/dev/null; then
            git lfs track "*.zip"
        fi

        # Ajouter un fichier initial si le répertoire est vide
        if [ -z "$(ls -A .)" ]; then
            echo "Ajout d'un fichier placeholder .gitkeep..."
            touch .gitkeep
            git add .gitkeep
        else
            add_files_to_git
        fi

        echo -e "# Ignorés\n*.log\n*.tmp\n.DS_Store\nnode_modules/\nvendor/" > .gitignore
        git add .gitignore

        git commit -m "Initial commit"
        git branch -M "$DEFAULT_BRANCH"
        git remote add origin "https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$(basename "$dir_path").git"

        echo "Envoi des fichiers vers GitHub..."
        git push -u origin "$DEFAULT_BRANCH"
    else
        echo "Le dépôt Git local existe déjà dans $dir_path."
    fi
}


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

# Parcours des répertoires dans BASE_PATH
for dir in "$BASE_PATH"/*; do
    if [ -d "$dir" ]; then
        repo_name=$(basename "$dir")

        # Vérifier si le dépôt existe sur GitHub
        echo "Vérification de l'existence du dépôt $repo_name sur GitHub..."
        repo_exists=$(curl -u "$GITHUB_USER:$GITHUB_TOKEN" -s -o /dev/null -w "%{http_code}" https://api.github.com/repos/$GITHUB_USER/$repo_name)

        if [ "$repo_exists" -eq 404 ]; then
            create_github_repo "$repo_name"
        else
            echo "Le dépôt $repo_name existe déjà sur GitHub."
        fi

        # Initialiser le dépôt local
        initialize_local_repo "$dir"
    fi
done

# Fin du script
echo "Script create.sh terminé."