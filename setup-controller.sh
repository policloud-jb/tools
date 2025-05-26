#!/bin/bash

# ========================================
# Linux System Setup Script
# Manages packages, SSH keys, and Git configuration
# ========================================

# -------- COLORS --------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------- CONFIGURATION --------
OPS_USER="ops"
SSH_DIR="/home/${OPS_USER}/.ssh"
DEFAULT_GITHUB_USER="policloud-jb"
REPO_NAME="tools"

# Default Git configuration
DEFAULT_GIT_USER="ops"
DEFAULT_GIT_EMAIL="ops@policloud.com"

# Required packages
PACKAGES=(
    "openssh-server" "ntp" "ethtool" "ipmitool" "util-linux"
    "vim" "htop" "parted" "curl" "git" "lsscsi" "net-tools" 
    "wget" "lshw" "mdadm" "docker.io" "python3-pip" "ifenslave" 
    "ansible" "python3-openstackclient" "openstack-clients"
    "openstack-dashboard" "python3-pymysql" "glances" 
    "docker-compose" "termshark" "jq"
)

# -------- FUNCTIONS --------
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_step() {
    echo -e "${YELLOW}🔧 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

parse_arguments() {
    GIT_USER="$DEFAULT_GIT_USER"
    GIT_EMAIL="$DEFAULT_GIT_EMAIL"
    GITHUB_USER="$DEFAULT_GITHUB_USER"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                GIT_USER="$2"
                shift 2
                ;;
            -e|--email)
                GIT_EMAIL="$2"
                shift 2
                ;;
            -g|--github-user)
                GITHUB_USER="$2"
                shift 2
                ;;
            -r|--repo)
                REPO_NAME="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set the Git config URL after parsing arguments
    GIT_CONFIG_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/refs/heads/main/configure-git.sh"
    
    print_step "Git configuration will use: $GIT_USER <$GIT_EMAIL>"
    print_step "GitHub repository: $GITHUB_USER/$REPO_NAME"
}

show_usage() {
    echo -e "${BLUE}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo "Options:"
    echo "  -u, --user         Git username (default: $DEFAULT_GIT_USER)"
    echo "  -e, --email        Git email (default: $DEFAULT_GIT_EMAIL)"
    echo "  -g, --github-user  GitHub username/organization (default: $DEFAULT_GITHUB_USER)"
    echo "  -r, --repo         Repository name (default: $REPO_NAME)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --user 'John Doe' --email 'john@example.com'"
    echo "  $0 -u 'Jane Smith' -e 'jane@company.com' -g 'my-org'"
    echo "  $0 --github-user 'mycompany' --repo 'devops-tools'"
}

create_ops_user() {
    print_step "Creating ops user..."
    
    if id "$OPS_USER" &>/dev/null; then
        print_success "User $OPS_USER already exists"
    else
        useradd -m -s /bin/bash "$OPS_USER"
        usermod -aG sudo "$OPS_USER"
        print_success "User $OPS_USER created and added to sudo group"
    fi
    
    # Ensure SSH directory exists with correct permissions
    sudo -u "$OPS_USER" mkdir -p "$SSH_DIR"
    sudo -u "$OPS_USER" chmod 700 "$SSH_DIR"
}

install_packages() {
    print_step "Updating package lists..."
    apt update
    apt upgrade -y
    
    print_step "Installing required packages..."
    apt install -y "${PACKAGES[@]}"
    
    if [[ $? -eq 0 ]]; then
        print_success "All packages installed successfully"
    else
        print_error "Some packages failed to install"
        exit 1
    fi
}

generate_ssh_keys() {
    print_step "Generating SSH keys..."
    
    # Generate ops key (default)
    if [[ ! -f "${SSH_DIR}/id_ed25519" ]]; then
        print_step "Generating ops SSH key..."
        sudo -u "$OPS_USER" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "${SSH_DIR}/id_ed25519" -N ""
        print_success "Ops SSH key generated"
    else
        print_success "Ops SSH key already exists"
    fi
    
    # Generate GitHub deploy key
    if [[ ! -f "${SSH_DIR}/github_deploy" ]]; then
        print_step "Generating GitHub deploy SSH key..."
        sudo -u "$OPS_USER" ssh-keygen -t ed25519 -f "${SSH_DIR}/github_deploy" -C "github-deploy-key" -N ""
        print_success "GitHub deploy SSH key generated"
    else
        print_success "GitHub deploy SSH key already exists"
    fi
    
    # Set correct permissions
    sudo -u "$OPS_USER" chmod 600 "${SSH_DIR}"/*
    sudo -u "$OPS_USER" chmod 644 "${SSH_DIR}"/*.pub
}

configure_ssh_config() {
    print_step "Configuring SSH client..."
    
    SSH_CONFIG="${SSH_DIR}/config"
    
    # Create SSH config content
    SSH_CONFIG_CONTENT="# GitHub configuration
Host github.com
    HostName github.com
    IdentityFile ${SSH_DIR}/github_deploy
    IdentitiesOnly yes
    User git

# Network servers configuration
Host netsrv*
    IdentityFile ${SSH_DIR}/id_ed25519
    User ${OPS_USER}
"
    
    if [[ ! -f "$SSH_CONFIG" ]] || ! grep -q "github.com" "$SSH_CONFIG" 2>/dev/null; then
        echo "$SSH_CONFIG_CONTENT" | sudo -u "$OPS_USER" tee "$SSH_CONFIG" > /dev/null
        sudo -u "$OPS_USER" chmod 600 "$SSH_CONFIG"
        print_success "SSH config created"
    else
        print_success "SSH config already exists"
    fi
}

download_git_script() {
    print_step "Downloading Git configuration script..."
    
    SCRIPT_PATH="/home/${OPS_USER}/configure-git.sh"
    
    if sudo -u "$OPS_USER" wget -q -O "$SCRIPT_PATH" "$GIT_CONFIG_URL"; then
        sudo -u "$OPS_USER" chmod +x "$SCRIPT_PATH"
        print_success "Git configuration script downloaded to $SCRIPT_PATH"
    else
        print_error "Failed to download Git configuration script"
        return 1
    fi
}

run_git_configuration() {
    print_step "Configuring Git globally..."
    
    # Set global Git configuration
    sudo -u "$OPS_USER" git config --global user.name "$GIT_USER"
    sudo -u "$OPS_USER" git config --global user.email "$GIT_EMAIL"
    sudo -u "$OPS_USER" git config --global init.defaultBranch main
    sudo -u "$OPS_USER" git config --global pull.rebase false
    
    print_success "Git global configuration completed"
    print_step "Git user: $GIT_USER"
    print_step "Git email: $GIT_EMAIL"
    
    print_step "Running Git configuration script..."
    
    SCRIPT_PATH="/home/${OPS_USER}/configure-git.sh"
    
    if [[ -f "$SCRIPT_PATH" ]]; then
        print_step "Executing Git configuration as $OPS_USER user..."
        echo -e "${YELLOW}Note: You may need to provide GitHub token and repository details${NC}"
        
        # Run the script as ops user
        sudo -u "$OPS_USER" bash "$SCRIPT_PATH"
        
        if [[ $? -eq 0 ]]; then
            print_success "Git configuration script completed successfully"
        else
            print_error "Git configuration script encountered an error"
        fi
    else
        print_error "Git configuration script not found at $SCRIPT_PATH"
    fi
}

setup_docker() {
    print_step "Configuring Docker..."
    
    # Add ops user to docker group
    usermod -aG docker "$OPS_USER"
    
    # Enable and start docker service
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker configured and started"
}

display_summary() {
    print_header "SETUP COMPLETE"
    
    echo -e "${GREEN}✅ System setup completed successfully!${NC}\n"
    
    echo -e "${BLUE}📋 Summary:${NC}"
    echo "• User '$OPS_USER' created with sudo privileges"
    echo "• All required packages installed"
    echo "• Git configured globally:"
    echo "  - User: $GIT_USER"
    echo "  - Email: $GIT_EMAIL"
    echo "• GitHub repository: $GITHUB_USER/$REPO_NAME"
    echo "• SSH keys generated:"
    echo "  - ${SSH_DIR}/id_ed25519 (ops key)"
    echo "  - ${SSH_DIR}/github_deploy (GitHub deploy key)"
    echo "• SSH config configured for GitHub and network servers"
    echo "• Docker service enabled and started"
    echo "• Git configuration script executed"
    
    echo -e "\n${YELLOW}📝 Next Steps:${NC}"
    echo "1. Switch to ops user: sudo su - $OPS_USER"
    echo "2. Verify Git repository was cloned successfully"
    echo "3. Setup MAAS/operations/inventory/mine-agents as required"
    
    echo -e "\n${BLUE}🔑 Public Keys:${NC}"
    echo "Ops key:"
    sudo -u "$OPS_USER" cat "${SSH_DIR}/id_ed25519.pub" 2>/dev/null || echo "  (not found)"
    echo ""
    echo "GitHub deploy key:"
    sudo -u "$OPS_USER" cat "${SSH_DIR}/github_deploy.pub" 2>/dev/null || echo "  (not found)"
}

# -------- MAIN EXECUTION --------
main() {
    print_header "Linux System Setup Script"
    
    parse_arguments "$@"
    check_root
    create_ops_user
    install_packages
    generate_ssh_keys
    configure_ssh_config
    download_git_script
    setup_docker
    run_git_configuration
    display_summary
}

# Run main function
main "$@"
