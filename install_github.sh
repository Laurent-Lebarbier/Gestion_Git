#!/bin/bash
# =============================================================
# install_github.sh — Configure SSH et enregistre la clé sur GitHub
# Usage : bash install_github.sh
# =============================================================
source "$(dirname "$0")/lib_common.sh"
load_env
check_deps curl jq ssh-keygen ssh-agent

KEY_FILE="$HOME/.ssh/id_ed25519"
KEY_COMMENT="$GITHUB_USER@$(hostname)"

echo "=== Configuration SSH pour GitHub ==="

# Vérifier si une clé SSH existe déjà
if [ -f "$KEY_FILE" ]; then
    echo "⚠️  Une clé SSH existe déjà : $KEY_FILE"
    read -rp "Voulez-vous la remplacer ? (oui/non) : " replace
    if [ "$replace" != "oui" ]; then
        echo "Opération annulée. La clé existante sera utilisée."
    else
        echo "Génération d'une nouvelle clé SSH (ed25519)..."
        ssh-keygen -t ed25519 -C "$KEY_COMMENT" -f "$KEY_FILE" -N ""
    fi
else
    echo "Génération d'une nouvelle clé SSH (ed25519)..."
    ssh-keygen -t ed25519 -C "$KEY_COMMENT" -f "$KEY_FILE" -N ""
fi

# Démarrer l'agent SSH et ajouter la clé.
# Note : cet agent ne survit pas à ce script (nouveau processus à chaque
# exécution). Ce n'est pas gênant pour git/push/pull car la clé est au
# chemin par défaut ($KEY_FILE) : ssh la charge automatiquement sans agent.
# On réutilise un agent déjà lancé dans la session si possible, plutôt que
# d'en empiler un nouveau à chaque appel.
if [ -z "${SSH_AUTH_SOCK:-}" ] || ! ssh-add -l &>/dev/null; then
    echo "Démarrage de l'agent SSH..."
    eval "$(ssh-agent -s)"
else
    echo "Agent SSH déjà actif, réutilisation."
fi
ssh-add "$KEY_FILE"

# Lire la clé publique
PUBLIC_KEY=$(cat "${KEY_FILE}.pub")
if [ -z "$PUBLIC_KEY" ]; then
    echo "❌ Impossible de lire la clé publique."
    exit 1
fi

# Vérifier si la clé est déjà enregistrée sur GitHub.
# L'API renvoie la clé SANS le commentaire final (user@host) : on compare
# donc uniquement "type + clé" (les deux premiers champs).
echo "Vérification des clés existantes sur GitHub..."
KEY_BODY=$(awk '{print $1" "$2}' "${KEY_FILE}.pub")
keys_json=$(github_api GET "/user/keys")
if ! echo "$keys_json" | jq -e 'type == "array"' &>/dev/null; then
    echo "❌ Impossible de lister vos clés SSH GitHub :"
    echo "$keys_json" | jq -r '.message // .' 2>/dev/null || echo "$keys_json"
    echo "   Le token doit avoir le scope 'admin:public_key' (ou 'write:public_key' + 'read:public_key')."
    exit 1
fi

if echo "$keys_json" | jq -e --arg k "$KEY_BODY" 'any(.[]; .key == $k)' &>/dev/null; then
    echo "✅ Cette clé SSH est déjà enregistrée sur GitHub."
else
    echo "Ajout de la clé SSH sur GitHub..."
    TITLE="${KEY_COMMENT}_$(date +%Y%m%d)"
    payload=$(jq -nc --arg t "$TITLE" --arg k "$PUBLIC_KEY" '{title: $t, key: $k}')
    response=$(github_api POST "/user/keys" "$payload")
    if echo "$response" | grep -q '"id"'; then
        echo "✅ Clé SSH ajoutée avec succès sur GitHub."
    else
        echo "❌ Erreur lors de l'ajout de la clé SSH :"
        echo "$response"
        exit 1
    fi
fi

# Ajouter github.com aux known_hosts si absent, en vérifiant l'empreinte
# officielle publiée par GitHub (évite d'accepter une fausse clé serveur)
GITHUB_ED25519_FP="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
if ! ssh-keygen -F github.com &>/dev/null; then
    echo "Ajout de github.com aux known_hosts..."
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    scanned=$(ssh-keyscan -t ed25519 github.com 2>/dev/null)
    fp=$(echo "$scanned" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
    if [ "$fp" = "$GITHUB_ED25519_FP" ]; then
        echo "$scanned" >> ~/.ssh/known_hosts
        echo "✅ Empreinte GitHub vérifiée."
    else
        echo "❌ Empreinte inattendue pour github.com ($fp) — known_hosts non modifié."
        echo "   Vérifiez sur https://docs.github.com/fr/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints"
        exit 1
    fi
fi

# Tester la connexion SSH
echo "Test de la connexion SSH avec GitHub..."
ssh_output=$(ssh -T git@github.com 2>&1)
if echo "$ssh_output" | grep -q "successfully authenticated"; then
    echo "✅ Connexion SSH à GitHub fonctionnelle."
else
    echo "⚠️  Réponse GitHub : $ssh_output"
fi

echo ""
echo "=== Installation terminée ==="
echo "Votre clé publique :"
echo "$PUBLIC_KEY"
