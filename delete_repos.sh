#!/bin/bash
# Charger les variables d'environnement depuis .env si présent
[ -f .env ] && export $(grep -v '^#' .env | xargs)

# Configuration
GITHUB_USER="Laurent-Lebarbier"  # Remplacez par votre nom d'utilisateur GitHub
GITHUB_TOKEN="${GITHUB_TOKEN:?Veuillez définir la variable d environnement GITHUB_TOKEN}"

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

# Confirmation avant de supprimer
echo "Les dépôts suivants seront supprimés :"
echo "$repos"
read -p "Êtes-vous sûr de vouloir supprimer tous ces dépôts ? (oui/non) " confirmation

if [[ "$confirmation" != "oui" ]]; then
    echo "Opération annulée."
    exit 0
fi

# Suppression de chaque dépôt
for repo_name in $repos; do
    echo "Suppression du dépôt $repo_name..."
    response=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_USER/$repo_name")

    if [ "$response" -eq 204 ]; then
        echo "Dépôt $repo_name supprimé avec succès."
    else
        echo "Échec de la suppression du dépôt $repo_name. Code HTTP : $response"
    fi
done

echo "Toutes les opérations sont terminées."