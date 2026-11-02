#!/usr/bin/env bash
# ==============================================================================
# Script: network_services_manager.sh
# Descrição: Automação modular para instalação, configuração e gerenciamento de
#            serviços de rede corporativos no Linux (Debian/Ubuntu) via whiptail.
# Autor: Eusébio Augusto Munene
# ==============================================================================

set -o pipefail

# ------------------------------------------------------------------------------
# 1. Verificação de Privilégios e Pré-requisitos
# ------------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[1;31m[ERRO] Este script deve ser executado com privilégios de superusuário (root/sudo).\e[0m" >&2
    exit 1
fi

# Instalação silenciosa do whiptail caso esteja ausente
if ! command -v whiptail >/dev/null 2>&1; then
    echo "[INFO] Pacote 'whiptail' ausente. Instalando silenciosamente..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq whiptail >/dev/null 2>&1
    if ! command -v whiptail >/dev/null 2>&1; then
        echo -e "\e[1;31m[ERRO] Falha crítica ao instalar o 'whiptail'. Verifique seus repositórios.\e[0m" >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 2. Carregamento de Bibliotecas e Módulos
# ------------------------------------------------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bibliotecas Centrais
# shellcheck source=/dev/null
source "$BASE_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/lib/network_utils.sh"

# Módulos de Serviços
# shellcheck source=/dev/null
source "$BASE_DIR/modules/dnsmasq/dnsmasq.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/modules/bind9/bind9.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/modules/samba/samba_ad.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/modules/wireguard/wireguard.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/modules/squid/squid.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/modules/ufw/ufw.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/modules/netplan/netplan.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/modules/dashboard/dashboard.sh"

log_message "INFO" "Sessão do Network Services Manager inicializada."

# ------------------------------------------------------------------------------
# 3. Loop Principal e Menu Interativo
# ------------------------------------------------------------------------------
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Gerenciador de Serviços de Rede Corporativos" \
            --menu "Ambiente: Debian / Ubuntu | Logs: /var/log/network_services_manager.log\nSelecione o serviço ou módulo desejado:" 20 74 9 \
            "1" "Dnsmasq (DHCP & DNS Integrado - Moderno & Leve)" \
            "2" "DNS Server (Bind9 - Cache & Forwarders)" \
            "3" "Active Directory Domain Controller (Samba 4 AD DC)" \
            "4" "VPN Server (WireGuard - Servidor, Clientes & QR Code)" \
            "5" "Proxy Server (Squid - Cache & Blacklist de Sites)" \
            "6" "Firewall (UFW - Regras, Perfis Corporativos & Status)" \
            "7" "Configuração de IP Estático (Netplan)" \
            "8" "Painel de Status Geral dos Serviços & Logs" \
            "9" "Sair" 3>&1 1>&2 2>&3)

        local exit_status=$?

        # Trata ESC ou Cancelar como confirmação de encerramento
        if [[ $exit_status -ne 0 || "$choice" == "9" ]]; then
            if whiptail --title "Confirmar Saída" --yesno "Deseja realmente encerrar o gerenciador?" 8 50; then
                clear
                log_message "INFO" "Sessão encerrada pelo usuário."
                echo "Gerenciador de Serviços finalizado com sucesso."
                exit 0
            fi
            continue
        fi

        case "$choice" in
            1) configure_dnsmasq ;;
            2) configure_dns_bind9 ;;
            3) configure_samba_ad_dc ;;
            4) manage_wireguard_menu ;;
            5) manage_squid_menu ;;
            6) manage_ufw_firewall ;;
            7) configure_static_ip_netplan ;;
            8) show_general_status_dashboard ;;
            *) whiptail --title "Aviso" --msgbox "Opção inválida." 8 40 ;;
        esac
    done
}

# Inicialização do loop interativo
main_menu
