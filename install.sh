#!/usr/bin/env bash
# ==============================================================================
# Script de Instalação e Bootstrap - Network Services Manager
# Repositório: https://github.com/emuneme/script-linux.git
# ==============================================================================

set -e

# Verificação de superusuário
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[1;31m[ERRO] Este instalador deve ser executado com privilégios de root (sudo).\e[0m" >&2
    exit 1
fi

INSTALL_DIR="/opt/network-services-manager"
REPO_URL="https://github.com/emuneme/script-linux.git"
BIN_LINK="/usr/local/bin/netmanager"

echo "==> [1/4] Verificando e instalando pré-requisitos essenciais (git, curl, whiptail)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq git curl whiptail >/dev/null 2>&1

echo "==> [2/4] Sincronizando repositório em $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
    cd "$INSTALL_DIR"
    git fetch origin main >/dev/null 2>&1 || true
    git reset --hard origin/main >/dev/null 2>&1 || true
else
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
fi

echo "==> [3/4] Configurando permissões nos módulos..."
chmod +x "$INSTALL_DIR/network_services_manager.sh"
chmod +x "$INSTALL_DIR/lib/"*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/modules/"*/*.sh 2>/dev/null || true

echo "==> [4/4] Criando atalho global no sistema ($BIN_LINK)..."
ln -sf "$INSTALL_DIR/network_services_manager.sh" "$BIN_LINK"

echo ""
echo "======================================================================"
echo " Network Services Manager instalado com sucesso!"
echo " Atalho global configurado: 'sudo netmanager'"
echo " Repositório: $REPO_URL"
echo "======================================================================"
echo ""

# Se conectado a um terminal interativo, inicia o gerenciador diretamente
if [[ -r /dev/tty ]]; then
    echo "Iniciando a interface interativa..."
    sleep 1
    exec "$BIN_LINK" < /dev/tty
else
    echo "Instalação concluída. Para iniciar, execute:"
    echo "  sudo netmanager"
fi

