#!/bin/bash

# -------- COLORS --------
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# -------- CHECK DEPENDENCIES --------
command -v curl >/dev/null 2>&1 || { echo "❌ curl is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ jq is required"; exit 1; }

# -------- LOAD SSH KEYS --------
SSH_DIR="$HOME/.ssh"
PUB_KEYS=($(ls ${SSH_DIR}/*.pub 2>/dev/null))

if [ ${#PUB_KEYS[@]} -eq 0 ]; then
    echo "❌ No public SSH keys found in ${SSH_DIR}"
    exit 1
fi

echo "🔐 Available SSH public keys:"
select PUB_KEY_FILE in "${PUB_KEYS[@]}"; do
    if [[ -n "$PUB_KEY_FILE" ]]; then
        break
    else
        echo "❌ Invalid selection."
    fi
done

# -------- GET PUBLIC KEY CONTENT --------
PUB_KEY_CONTENT=$(cat "${PUB_KEY_FILE}")

# -------- PROMPT FOR GITHUB DETAILS --------
read -rp "👤 GitHub user/org (e.g., policloud or yourusername): " GITHUB_USER
read -rp "📦 Repository name (e.g., my-repo): " REPO_NAME
read -rp "🏷️  Deploy key title (e.g., auto-deploy-$(hostname -s)): " KEY_TITLE
read -rp "🔐 GitHub token (with repo + admin:public_key scopes): " -s GITHUB_TOKEN
echo ""

# -------- ADD DEPLOY KEY --------
echo -e "🚀 Adding deploy key to ${GITHUB_USER}/${REPO_NAME}..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}/keys \
  -d "{\"title\":\"${KEY_TITLE}\",\"key\":\"${PUB_KEY_CONTENT}\",\"read_only\":true}")

if [[ "$RESPONSE" == "201" ]]; then
    echo -e "${GREEN}✅ Deploy key added successfully!${NC}"
elif [[ "$RESPONSE" == "422" ]]; then
    echo -e "${RED}⚠️ Key already exists in the repository.${NC}"
else
    echo -e "${RED}❌ Failed to add key. HTTP status: $RESPONSE${NC}"
fi
