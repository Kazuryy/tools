#!/usr/bin/env bash
# Configuration SSH + Git pour Gitea (SSH et/ou remote configurables séparément)
# Usage : bash setup-gitea.sh

set -e

# ─── Couleurs ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERR]${RESET}  $*"; exit 1; }
step()    { echo -e "\n${BOLD}══ $* ${RESET}"; }

# ─── Détection OS ────────────────────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}
OS=$(detect_os)

# ─── Dépendances ─────────────────────────────────────────────────────────────
check_deps() {
    step "Vérification des dépendances"
    command -v git >/dev/null 2>&1 || error "Git n'est pas installé."
    if [[ "$SKIP_SSH" != "y" ]]; then
        command -v ssh-keygen >/dev/null 2>&1 || error "ssh-keygen introuvable."
    fi
    success "Dépendances OK."
}

# ─── Choix des étapes ─────────────────────────────────────────────────────────
ask_skip_options() {
    step "Que voulez-vous faire ?"

    echo ""
    read -rp "SSH déjà configurée (clé + ~/.ssh/config) ? Sauter cette étape ? (o/N) : " _skip
    [[ "$_skip" == "o" || "$_skip" == "O" ]] && SKIP_SSH="y" || SKIP_SSH="n"

    echo ""
    read -rp "Repo déjà cloné ? Travailler sur un dossier existant ? (o/N) : " _existing
    [[ "$_existing" == "o" || "$_existing" == "O" ]] && USE_EXISTING_REPO="y" || USE_EXISTING_REPO="n"
}

# ─── Informations utilisateur ────────────────────────────────────────────────
collect_user_info() {
    step "Informations utilisateur"

    DEFAULT_NAME=$(git config --global user.name 2>/dev/null || echo "")
    DEFAULT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

    read -rp "Votre prénom et nom${DEFAULT_NAME:+ [$DEFAULT_NAME]} : " GIT_NAME
    GIT_NAME="${GIT_NAME:-$DEFAULT_NAME}"
    [[ -z "$GIT_NAME" ]] && error "Le nom ne peut pas être vide."

    read -rp "Votre email Gitea${DEFAULT_EMAIL:+ [$DEFAULT_EMAIL]} : " GIT_EMAIL
    GIT_EMAIL="${GIT_EMAIL:-$DEFAULT_EMAIL}"
    [[ -z "$GIT_EMAIL" ]] && error "L'email ne peut pas être vide."

    while true; do
        read -rp "URL SSH du dépôt (ex: gitea@host:org/repo.git  ou  ssh://git@host:2222/org/repo.git) : " REPO_SSH_URL
        [[ -z "$REPO_SSH_URL" ]] && { warn "L'URL ne peut pas être vide."; continue; }
        if [[ "$REPO_SSH_URL" =~ ^ssh://([^@]+)@([^:/]+)(:([0-9]+))?/(.+)$ ]]; then
            SSH_USER="${BASH_REMATCH[1]}"
            SSH_HOST="${BASH_REMATCH[2]}"
            URL_PORT="${BASH_REMATCH[4]}"
            break
        elif [[ "$REPO_SSH_URL" =~ ^([^@]+)@([^:]+):.+ ]]; then
            SSH_USER="${BASH_REMATCH[1]}"
            SSH_HOST="${BASH_REMATCH[2]}"
            URL_PORT=""
            break
        fi
        warn "URL invalide — formats acceptés : user@host:org/repo.git  ou  ssh://user@host:port/org/repo.git"
    done

    read -rp "Votre nom d'utilisateur Gitea (login du compte, ex: alice) : " GITEA_USERNAME
    GITEA_USERNAME=$(echo "$GITEA_USERNAME" | tr '[:upper:]' '[:lower:]')
    [[ -z "$GITEA_USERNAME" ]] && error "Le nom d'utilisateur ne peut pas être vide."
    SSH_KEY_PATH="$HOME/.ssh/id_ed25519_gitea_${GITEA_USERNAME}"
    info "Clé SSH : $SSH_KEY_PATH"

    if [[ -n "$URL_PORT" ]]; then
        GITEA_SSH_PORT="$URL_PORT"
        info "Port SSH extrait de l'URL : $GITEA_SSH_PORT"
    elif [[ "$SKIP_SSH" != "y" ]]; then
        read -rp "Port SSH de Gitea [22] : " GITEA_SSH_PORT
        GITEA_SSH_PORT="${GITEA_SSH_PORT:-22}"
    else
        EXISTING_PORT=$(grep -A5 "Host $SSH_HOST" "$HOME/.ssh/config" 2>/dev/null | grep Port | awk '{print $2}' | head -1)
        GITEA_SSH_PORT="${EXISTING_PORT:-22}"
        info "Port SSH détecté depuis ~/.ssh/config : $GITEA_SSH_PORT"
    fi

    if [[ "$USE_EXISTING_REPO" == "y" ]]; then
        read -rp "Chemin vers le dossier du repo existant : " REPO_DIR
        REPO_DIR="${REPO_DIR/#\~/$HOME}"
        [[ -d "$REPO_DIR/.git" ]] || error "Pas de dépôt Git trouvé dans '$REPO_DIR'."
    else
        read -rp "Dossier de destination pour le clone (défaut: ./repo) : " REPO_DIR
        REPO_DIR="${REPO_DIR:-repo}"
        REPO_DIR="${REPO_DIR/#\~/$HOME}"
    fi

    info "Nom    : $GIT_NAME"
    info "Email  : $GIT_EMAIL"
    info "Gitea  : $SSH_USER@$SSH_HOST:$GITEA_SSH_PORT"
    info "Dépôt  : $REPO_SSH_URL → $REPO_DIR"
}

# ─── Génération clé SSH ───────────────────────────────────────────────────────
generate_ssh_key() {
    step "Génération de la clé SSH ed25519"

    if [[ -f "$SSH_KEY_PATH" ]]; then
        warn "Une clé existe déjà à $SSH_KEY_PATH"
        read -rp "Écraser ? (o/N) : " OVERWRITE
        [[ "$OVERWRITE" != "o" && "$OVERWRITE" != "O" ]] && { info "Clé existante conservée."; return; }
    fi

    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY_PATH"
    chmod 600 "$SSH_KEY_PATH"
    success "Clé générée : $SSH_KEY_PATH"
}

# ─── Agent SSH ────────────────────────────────────────────────────────────────
configure_ssh_agent() {
    step "Configuration de l'agent SSH"

    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true

    if [[ "$OS" == "macos" ]]; then
        ssh-add --apple-use-keychain "$SSH_KEY_PATH" 2>/dev/null || \
        ssh-add "$SSH_KEY_PATH"
    else
        ssh-add "$SSH_KEY_PATH"
    fi

    success "Clé ajoutée à l'agent SSH."
}

# ─── ~/.ssh/config ────────────────────────────────────────────────────────────
configure_ssh_config() {
    step "Configuration de ~/.ssh/config"

    SSH_CONFIG="$HOME/.ssh/config"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    BLOCK="
Host $SSH_HOST
    HostName $SSH_HOST
    Port $GITEA_SSH_PORT
    User $SSH_USER
    IdentityFile $SSH_KEY_PATH
    IdentitiesOnly yes"

    if grep -q "Host $SSH_HOST" "$SSH_CONFIG" 2>/dev/null; then
        warn "Une entrée pour $SSH_HOST existe déjà dans ~/.ssh/config. Pas de modification."
    else
        echo "$BLOCK" >> "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
        success "Entrée ajoutée dans ~/.ssh/config."
    fi
}

# ─── Vérification fingerprint + signature si demandée ────────────────────────
verify_key_on_platforms() {
    step "Vérification de la clé"

    LOCAL_FP=$(ssh-keygen -lf "${SSH_KEY_PATH}.pub" | awk '{print $2}')

    echo ""
    echo -e "${BOLD}Fingerprint de votre clé locale :${RESET}"
    echo -e "  ${GREEN}$LOCAL_FP${RESET}"
    echo ""
    echo "Comparez ce fingerprint avec celui affiché dans vos paramètres SSH :"
    echo -e "  • Gitea  → Settings → SSH/GPG Keys"
    echo ""
    read -rp "Le fingerprint correspond ? (o/N) : " CONFIRMED
    [[ "$CONFIRMED" != "o" && "$CONFIRMED" != "O" ]] && {
        warn "Ajoutez la clé sur Gitea puis relancez cette vérification."
        error "Arrêt."
    }
    success "Fingerprint confirmé."

    echo ""
    read -rp "La plateforme vous demande-t-elle de signer un token de vérification ? (o/N) : " NEEDS_SIG
    if [[ "$NEEDS_SIG" == "o" || "$NEEDS_SIG" == "O" ]]; then
        step "Signature du token de vérification"
        read -rp "Token : " VERIFY_TOKEN
        [[ -z "$VERIFY_TOKEN" ]] && error "Token vide."

        info "Génération de la signature..."
        SIGNATURE=$(echo -n "$VERIFY_TOKEN" | ssh-keygen -Y sign -n gitea -f "$SSH_KEY_PATH" 2>/dev/null)
        [[ -z "$SIGNATURE" ]] && error "La signature a échoué."

        echo ""
        echo -e "${BOLD}Copiez ce bloc dans le champ 'Armored SSH signature' :${RESET}"
        echo ""
        echo -e "${GREEN}$SIGNATURE${RESET}"
        echo ""
        read -rp "Vérification effectuée ? Appuyez sur Entrée pour continuer..."
        success "Signature de possession complétée."
    fi
}

# ─── Ajout clé sur Gitea + test connexion ────────────────────────────────────
add_key_to_gitea_and_test() {
    step "Ajout de la clé publique sur Gitea"

    echo ""
    echo -e "${BOLD}Copiez cette clé publique et ajoutez-la sur Gitea :${RESET}"
    echo -e "${YELLOW}Gitea → Settings → SSH/GPG Keys → Add Key${RESET}"
    echo ""
    cat "${SSH_KEY_PATH}.pub"
    echo ""
    read -rp "Appuyez sur Entrée une fois la clé ajoutée sur Gitea..."

    verify_key_on_platforms

    step "Test de la connexion SSH"

    info "Test en cours : $SSH_USER@$SSH_HOST (port $GITEA_SSH_PORT)..."
    SSH_TEST=$(ssh -T \
        -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        -p "$GITEA_SSH_PORT" \
        "$SSH_USER@$SSH_HOST" 2>&1 || true)

    if echo "$SSH_TEST" | grep -qi "successfully"; then
        success "Connexion SSH à Gitea réussie !"
    else
        warn "Connexion échouée. Détail :"
        echo "$SSH_TEST"
        echo ""
        info "Commande manuelle pour débugger :"
        info "  ssh -vT -i $SSH_KEY_PATH -p $GITEA_SSH_PORT $SSH_USER@$SSH_HOST"
        read -rp "Continuer quand même ? (o/N) : " CONTINUE
        [[ "$CONTINUE" != "o" && "$CONTINUE" != "O" ]] && error "Arrêt."
    fi
}

# ─── Test connexion SSH (sans reconfiguration) ────────────────────────────────
test_ssh_only() {
    step "Test de la connexion SSH existante"

    [[ -f "$SSH_KEY_PATH" ]] || error "Clé $SSH_KEY_PATH introuvable. Relancez sans l'option skip SSH."

    info "Test en cours : $SSH_USER@$SSH_HOST (port $GITEA_SSH_PORT)..."
    SSH_TEST=$(ssh -T \
        -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=no \
        -o BatchMode=yes \
        -p "$GITEA_SSH_PORT" \
        "$SSH_USER@$SSH_HOST" 2>&1 || true)

    if echo "$SSH_TEST" | grep -qi "successfully"; then
        success "Connexion SSH à Gitea réussie !"
    else
        warn "Connexion SSH échouée. Détail :"
        echo "$SSH_TEST"
        warn "Si le problème persiste, relancez sans l'option skip SSH pour reconfigurer."
    fi
}

# ─── Clone ou repo existant ───────────────────────────────────────────────────
setup_repo() {
    if [[ "$USE_EXISTING_REPO" == "y" ]]; then
        step "Configuration du remote sur le repo existant"

        CURRENT_REMOTE=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "")
        if [[ -n "$CURRENT_REMOTE" ]]; then
            info "Remote actuel : $CURRENT_REMOTE"
            git -C "$REPO_DIR" remote set-url origin "$REPO_SSH_URL"
            success "Remote mis à jour → $REPO_SSH_URL"
        else
            git -C "$REPO_DIR" remote add origin "$REPO_SSH_URL"
            success "Remote ajouté → $REPO_SSH_URL"
        fi
    else
        step "Clone du dépôt"

        if [[ -d "$REPO_DIR" ]]; then
            warn "Le dossier '$REPO_DIR' existe déjà."
            read -rp "Continuer dans ce dossier ? (o/N) : " USE_EXISTING
            [[ "$USE_EXISTING" != "o" && "$USE_EXISTING" != "O" ]] && error "Arrêt. Choisissez un autre dossier."
        else
            git clone "$REPO_SSH_URL" "$REPO_DIR"
            success "Dépôt cloné dans $REPO_DIR"
        fi
    fi
}

# ─── Méthode de signature ─────────────────────────────────────────────────────
choose_signing_method() {
    step "Méthode de signature des commits"
    echo "  1) SSH  — Réutilise votre clé SSH (recommandé)"
    echo "  2) GPG  — Méthode classique"
    echo ""
    read -rp "Votre choix [1/2] : " SIGN_METHOD
    if [[ "$SIGN_METHOD" != "1" && "$SIGN_METHOD" != "2" ]]; then
        warn "Choix invalide, 1 sélectionné par défaut."
        SIGN_METHOD=1
    fi
}

# ─── Config git locale ────────────────────────────────────────────────────────
configure_git_local() {
    step "Configuration Git locale dans $REPO_DIR"

    git -C "$REPO_DIR" config user.name "$GIT_NAME"
    git -C "$REPO_DIR" config user.email "$GIT_EMAIL"

    if [[ "$SIGN_METHOD" == "1" ]]; then
        configure_ssh_signing
    else
        configure_gpg_signing
    fi

    success "Config Git locale appliquée (votre config globale est intacte)."
}

configure_ssh_signing() {
    git -C "$REPO_DIR" config gpg.format ssh
    git -C "$REPO_DIR" config user.signingkey "${SSH_KEY_PATH}.pub"
    git -C "$REPO_DIR" config commit.gpgsign true
    git -C "$REPO_DIR" config tag.gpgsign true

    ALLOWED_SIGNERS="$HOME/.ssh/allowed_signers"
    PUBKEY=$(cat "${SSH_KEY_PATH}.pub")
    if ! grep -qF "$PUBKEY" "$ALLOWED_SIGNERS" 2>/dev/null; then
        echo "$GIT_EMAIL $PUBKEY" >> "$ALLOWED_SIGNERS"
    fi
    git -C "$REPO_DIR" config gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"

    success "Signature SSH configurée."
    warn "Ajoutez votre clé publique dans Gitea pour la vérification des commits :"
    warn "Gitea → Settings → SSH/GPG Keys → Manage GPG Keys → Add Key"
}

configure_gpg_signing() {
    command -v gpg >/dev/null 2>&1 || error "gpg n'est pas installé."

    info "Génération d'une clé GPG ed25519..."
    gpg --full-generate-key

    echo ""
    gpg --list-secret-keys --keyid-format=long
    echo ""
    read -rp "Collez l'ID de votre clé (ex: ABCD1234EFGH5678) : " GPG_KEY_ID
    [[ -z "$GPG_KEY_ID" ]] && error "L'ID de clé ne peut pas être vide."

    git -C "$REPO_DIR" config user.signingkey "$GPG_KEY_ID"
    git -C "$REPO_DIR" config commit.gpgsign true
    git -C "$REPO_DIR" config tag.gpgsign true

    if [[ "$OS" == "macos" ]]; then
        SHELL_RC="$HOME/.zshrc"
        [[ "$SHELL" == *"bash"* ]] && SHELL_RC="$HOME/.bashrc"
        if ! grep -q "GPG_TTY" "$SHELL_RC" 2>/dev/null; then
            echo 'export GPG_TTY=$(tty)' >> "$SHELL_RC"
            info "GPG_TTY ajouté à $SHELL_RC."
        fi
    fi

    success "Signature GPG configurée."
    warn "Exportez et ajoutez votre clé sur Gitea :"
    warn "Gitea → Settings → SSH/GPG Keys → Manage GPG Keys → Add Key"
    echo ""
    gpg --armor --export "$GPG_KEY_ID"
}

# ─── Résumé ───────────────────────────────────────────────────────────────────
print_summary() {
    step "Tout est prêt"
    echo ""
    echo -e "${GREEN}${BOLD}Récapitulatif :${RESET}"
    [[ "$SKIP_SSH" != "y" ]] && echo "  Clé SSH            : $SSH_KEY_PATH"
    echo "  Dépôt              : $(realpath "$REPO_DIR")"
    echo "  Remote origin      : $(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo '—')"
    echo "  user.name (local)  : $(git -C "$REPO_DIR" config user.name)"
    echo "  user.email (local) : $(git -C "$REPO_DIR" config user.email)"
    echo "  gpg.format         : $(git -C "$REPO_DIR" config gpg.format 2>/dev/null || echo 'gpg (défaut)')"
    echo "  commit.gpgsign     : $(git -C "$REPO_DIR" config commit.gpgsign 2>/dev/null || echo 'non défini')"
    echo ""
    echo -e "${BOLD}Config globale (inchangée) :${RESET}"
    echo "  user.name  : $(git config --global user.name 2>/dev/null || echo '—')"
    echo "  user.email : $(git config --global user.email 2>/dev/null || echo '—')"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║   Configuration SSH & Git Remote — Gitea     ║${RESET}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${YELLOW}Votre config Git globale ne sera pas modifiée.${RESET}"
    echo ""

    ask_skip_options
    check_deps
    collect_user_info

    if [[ "$SKIP_SSH" != "y" ]]; then
        generate_ssh_key
        configure_ssh_agent
        configure_ssh_config
        add_key_to_gitea_and_test
    else
        test_ssh_only
    fi

    setup_repo
    choose_signing_method
    configure_git_local
    print_summary
}

main
