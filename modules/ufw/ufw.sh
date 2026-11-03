#!/usr/bin/env bash
# ==============================================================================
# modules/ufw/ufw.sh - Gerenciamento de Firewall UFW
# ==============================================================================

manage_ufw_firewall() {
    if ! command -v ufw >/dev/null 2>&1; then
        gauge_apt_install "Instalação do Firewall" "ufw"
    fi

    local tmp_ufw
    tmp_ufw=$(mktemp /tmp/netmgr_ufw.XXXXXX 2>/dev/null || echo "/tmp/netmgr_ufw.$$.tmp")

    while true; do
        whiptail --title "Gerenciamento de Firewall UFW" \
            --menu "Escolha a operação desejada para o UFW:" 17 68 6 \
            "1" "Ativar Firewall (ufw enable)" \
            "2" "Desativar Firewall (ufw disable)" \
            "3" "Liberar Porta Específica (Custom Port/Protocol)" \
            "4" "Liberar Perfis Corporativos (DHCP, DNS, Samba, WG, Squid, SSH)" \
            "5" "Visualizar Regras Ativas (ufw status numbered)" \
            "6" "Retornar ao Menu Principal" 2>"$tmp_ufw"

        local exit_status=$?
        local ufw_opt
        ufw_opt=$(cat "$tmp_ufw" 2>/dev/null | tr -d '\r\n[:space:]')
        : > "$tmp_ufw"

        [[ $exit_status -ne 0 || "$ufw_opt" == "6" ]] && break

        case "$ufw_opt" in
            1)
                ufw --force enable >> "$LOG_FILE" 2>&1
                whiptail --title "UFW" --msgbox "O Firewall UFW foi ATIVADO com sucesso." 8 50
                ;;
            2)
                ufw disable >> "$LOG_FILE" 2>&1
                whiptail --title "UFW" --msgbox "O Firewall UFW foi DESATIVADO." 8 50
                ;;
            3)
                local port
                port=$(prompt_valid_port "UFW - Liberar Porta" "Informe o número da porta a ser liberada:" "8080") || continue
                local proto
                proto=$(whiptail_capture --title "UFW - Protocolo" --menu "Selecione o protocolo:" 12 50 3 \
                    "tcp" "Protocolo TCP" \
                    "udp" "Protocolo UDP" \
                    "both" "Ambos (TCP e UDP)") || continue
                proto=$(echo "$proto" | tr -d '[:space:]')

                if [[ "$proto" == "both" ]]; then
                    ufw allow "${port}" >> "$LOG_FILE" 2>&1
                else
                    ufw allow "${port}/${proto}" >> "$LOG_FILE" 2>&1
                fi
                whiptail --title "UFW" --msgbox "Regra adicionada para a porta $port ($proto)." 8 52
                ;;
            4)
                {
                    echo 15; ufw allow 22/tcp comment "SSH Management" >> "$LOG_FILE" 2>&1
                    echo 30; ufw allow 67/udp comment "DHCP Server" >> "$LOG_FILE" 2>&1
                    echo 40; ufw allow 53 comment "DNS Server" >> "$LOG_FILE" 2>&1
                    echo 55; ufw allow 51820/udp comment "WireGuard VPN" >> "$LOG_FILE" 2>&1
                    echo 70; ufw allow 3128/tcp comment "Squid Proxy" >> "$LOG_FILE" 2>&1
                    echo 85
                    # Portas corporativas do Samba 4 AD DC
                    ufw allow 88 comment "Samba Kerberos" >> "$LOG_FILE" 2>&1
                    ufw allow 135/tcp comment "Samba MS RPC" >> "$LOG_FILE" 2>&1
                    ufw allow 138/udp comment "Samba NetBIOS Netlogon" >> "$LOG_FILE" 2>&1
                    ufw allow 139/tcp comment "Samba NetBIOS Session" >> "$LOG_FILE" 2>&1
                    ufw allow 389 comment "Samba LDAP" >> "$LOG_FILE" 2>&1
                    ufw allow 445/tcp comment "Samba SMB/CIFS" >> "$LOG_FILE" 2>&1
                    ufw allow 464 comment "Samba kpasswd" >> "$LOG_FILE" 2>&1
                    ufw allow 636/tcp comment "Samba LDAPS" >> "$LOG_FILE" 2>&1
                    ufw allow 3268/tcp comment "Samba Global Catalog" >> "$LOG_FILE" 2>&1
                    ufw allow 3269/tcp comment "Samba Global Catalog SSL" >> "$LOG_FILE" 2>&1
                    echo 100
                } | whiptail --title "UFW" --gauge "Aplicando perfis de portas corporativas..." 8 65 0
                whiptail --title "UFW" \
                    --msgbox "Perfis liberados com sucesso:\n- SSH (22/tcp)\n- DHCP (67/udp)\n- DNS (53)\n- WireGuard (51820/udp)\n- Squid Proxy (3128/tcp)\n- Samba AD DC (88, 135, 138, 139, 389, 445, 464, 636, 3268, 3269)" 15 65
                ;;
            5)
                local status_output
                status_output=$(ufw status numbered 2>&1)
                whiptail --title "UFW - Status e Regras Ativas" --scrolltext --msgbox "$status_output" 18 70
                ;;
        esac
    done
    rm -f "$tmp_ufw"
}

