#!/bin/bash

# Charger le token depuis le fichier .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Fichier .env non trouvé. Veuillez créer un fichier .env avec votre token GitHub."
    exit 1
fi

# Vérifiez si l'utilisateur a déjà une clé SSH
if [ -f ~/.ssh/id_rsa ]; then
    echo "Une clé SSH existe déjà. Voulez-vous la remplacer ? (y/n)"
    read replace
    if [ "$replace" != "y" ]; then
        echo "Opération annulée."
        exit 1
    fi
fi

# Génération d'une nouvelle clé SSH
echo "Génération d'une nouvelle clé SSH..."
ssh-keygen -t rsa -b 4096 -C "laurentlebarbier70@gmail.com" -f ~/.ssh/id_rsa -N ""

# Ajout de la clé SSH à l'agent SSH
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa

# Lire la clé publique
PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)

# Ajouter la clé SSH à GitHub via l'API
echo "Ajout de la clé SSH à GitHub..."
curl -H "Authorization: token $GITHUB_TOKEN" --data "{\"title\":\"$(hostname)_ssh_key\",\"key\":\"$PUBLIC_KEY\"}" https://api.github.com/user/keys

# Test de la connexion SSH avec GitHub
echo "Test de la connexion SSH avec GitHub..."
ssh -T git@github.com

echo "Script terminé."