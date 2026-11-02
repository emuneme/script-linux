#!/usr/bin/env bash
# ==============================================================================
# modules/samba/samba_ad.sh - Active Directory Domain Controller (Samba 4 AD DC)
# ==============================================================================

configure_samba_ad_dc() {
    # 1. Resolução preventiva de conflito na porta 53
    check_and_resolve_port_53_conflict "Samba AD DC (DNS Interno)" || return

    local realm
    realm=$(whiptail --title "Samba AD - Realm / Domínio FQDN" \
        --inputbox "Informe o Realm do Domínio (Ex: CORP.LOCAL):" 8 60 "CORP.LOCAL" 3>&1 1>&2 2>&3) || return
    realm=$(echo "$realm" | tr '[:lower:]' '[:upper:]')

    local domain_netbios
    domain_netbios=$(whiptail --title "Samba AD - Nome NetBIOS" \
        --inputbox "Informe o nome de Domínio NetBIOS (Ex: CORP):" 8 60 "CORP" 3>&1 1>&2 2>&3) || return
    domain_netbios=$(echo "$domain_netbios" | tr '[:lower:]' '[:upper:]')

    local admin_pass
    while true; do
        admin_pass=$(whiptail --title "Samba AD - Senha do Administrador" \
            --passwordbox "Defina a senha do Administrador do Domínio (Mínimo: maiúscula, minúscula, número e símbolo):" 9 65 3>&1 1>&2 2>&3) || return

        local admin_pass_confirm
        admin_pass_confirm=$(whiptail --title "Samba AD - Confirmação de Senha" \
            --passwordbox "Confirme a senha do Administrador:" 8 65 3>&1 1>&2 2>&3) || return

        if [[ "$admin_pass" == "$admin_pass_confirm" && -n "$admin_pass" ]]; then
            break
        else
            whiptail --title "Erro de Validação" --msgbox "As senhas não coincidem ou estão vazias. Tente novamente." 8 60
        fi
    done

    gauge_apt_install "Instalação Samba AD DC" "samba" "smbclient" "krb5-user" "winbind" "libpam-winbind" "libnss-winbind"

    local smb_conf="/etc/samba/smb.conf"
    local backup_file=""
    if [[ -f "$smb_conf" ]]; then
        backup_file="${smb_conf}.bak.$(date +%F_%T)"
        cp "$smb_conf" "$backup_file"
    fi

    {
        echo 20
        echo "XXX\nParando serviços legados e mascarando daemons não AD...\nXXX"
        systemctl stop smbd nmbd winbind >> "$LOG_FILE" 2>&1 || true
        systemctl disable smbd nmbd winbind >> "$LOG_FILE" 2>&1 || true
        systemctl mask smbd nmbd winbind >> "$LOG_FILE" 2>&1 || true

        echo 40
        echo "XXX\nEfetuando backup e remoção de /etc/samba/smb.conf...\nXXX"
        rm -f /etc/samba/smb.conf

        echo 65
        echo "XXX\nProvisionando Domínio Samba 4 AD DC...\nXXX"
        samba-tool domain provision \
            --use-rfc2307 \
            --realm="$realm" \
            --domain="$domain_netbios" \
            --server-role=dc \
            --dns-backend=SAMBA_INTERNAL \
            --adminpass="$admin_pass" >> "$LOG_FILE" 2>&1

        echo 85
        echo "XXX\nConfigurando Kerberos e inicializando serviço samba-ad-dc...\nXXX"
        [[ -f /var/lib/samba/private/krb5.conf ]] && cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

        systemctl unmask samba-ad-dc >> "$LOG_FILE" 2>&1 || true
        systemctl enable samba-ad-dc >> "$LOG_FILE" 2>&1
        systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1

        echo 100
        echo "XXX\nProvisionamento concluído!\nXXX"
        sleep 0.5
    } | whiptail --title "Provisionamento Samba AD" --gauge "Configurando controlador de domínio..." 8 65 0

    show_service_result "samba-ad-dc" "Samba 4 AD DC" "$backup_file"
}

