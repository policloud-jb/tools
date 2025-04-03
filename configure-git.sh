#!/bin/bash

# -------- COLORS --------
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

GITHUB_USER='policloud'
KEY_TITLE="deploy-$(hostname -s)"

sudo apt update
sudo apt install jq -y

# -------- CHECK DEPENDENCIES --------
for cmd in curl jq git; do
  command -v $cmd >/dev/null 2>&1 || { echo "❌ $cmd is required"; exit 1; }
done

# -------- LOAD SSH KEYS --------
SSH_DIR="$HOME/.ssh"
PUB_KEYS=($(ls ${SSH_DIR}/github_deploy.pub 2>/dev/null))


if [ ${#PUB_KEYS[@]} -eq 0 ]; then
    echo "❌ No public SSH keys found in ${SSH_DIR}"
    echo "🔐 Generating a new SSH key..."
    mkdir -p "${SSH_DIR}"
    chmod 700 "${SSH_DIR}"
    ssh-keygen -t ed25519 -C 'ops@policloud.com' -f "${SSH_DIR}/github_deploy" -N '' -q
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ SSH key generated at ${SSH_DIR}/github_deploy${NC}"
        PUB_KEYS=("${SSH_DIR}/github_deploy.pub")
    else
        echo -e "${RED}❌ Failed to generate SSH key${NC}"
        exit 1
    fi
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
KEY_PATH="${PUB_KEY_FILE%.pub}"

# -------- PROMPT FOR GITHUB DETAILS --------
# read -rp "👤 GitHub user/org (e.g., policloud): " GITHUB_USER
read -rp "📦 Repository name (e.g., my-repo): " REPO_NAME
CLONE_DIR="${HOME}/${REPO_NAME}"
# read -rp "🏷️  Deploy key title (default: deploy-$(hostname -s)): " KEY_TITLE
#KEY_TITLE="${KEY_TITLE:-deploy-$(hostname -s)}"
#read -rp "📁 Clone directory (default: ~/${REPO_NAME}): " CLONE_DIR
#CLONE_DIR="${CLONE_DIR:-$HOME/${REPO_NAME}}"
read -rp "🔐 GitHub token (with repo + admin:public_key scopes): " -s GITHUB_TOKEN
echo ""

# -------- ADD DEPLOY KEY --------
echo -e "\n🚀 Adding deploy key to ${GITHUB_USER}/${REPO_NAME}..."

RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null \
  -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}/keys \
  -d "{\"title\":\"${KEY_TITLE}\",\"key\":\"${PUB_KEY_CONTENT}\",\"read_only\":true}")

case "$RESPONSE" in
  201)
    echo -e "${GREEN}✅ Deploy key added successfully!${NC}" ;;
  422)
    echo -e "${RED}⚠️ Deploy key already exists, continuing...${NC}" ;;
  *)
    echo -e "${RED}❌ Failed to add key. HTTP status: $RESPONSE${NC}"
    exit 1 ;;
esac

# -------- SSH CONFIG --------
SSH_CONFIG="${SSH_DIR}/config"
if ! grep -q "${KEY_PATH}" "${SSH_CONFIG}" 2>/dev/null; then
    echo "🔧 Adding SSH config for GitHub..."
    echo "
Host github.com
    HostName github.com
    IdentityFile ${KEY_PATH}
    IdentitiesOnly yes
    User git
" >> "${SSH_CONFIG}"
    chmod 600 "${SSH_CONFIG}"
fi

# -------- CLONE REPO --------
echo -e "📥 Cloning repo to ${CLONE_DIR}...\n"

if [ -d "$CLONE_DIR/.git" ]; then
    echo "📁 Repo already exists. Pulling latest changes..."
    git -C "$CLONE_DIR" pull
else
    git clone "git@github.com:${GITHUB_USER}/${REPO_NAME}.git" "$CLONE_DIR"
fi

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Repo ready at ${CLONE_DIR}${NC}"
else
    echo -e "${RED}❌ Git operation failed.${NC}"
    exit 1
fi
