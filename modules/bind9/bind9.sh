#!/usr/bin/env bash
# ==============================================================================
# modules/bind9/bind9.sh - Servidor DNS Corporativo (Bind9)
# ==============================================================================

configure_dns_bind9() {
    # 1. Resolução preventiva de conflito na porta 53
    check_and_resolve_port_53_conflict "Bind9 DNS" || return

    local forwarders
    forwarders=$(whiptail_capture --title "Bind9 - Forwarders" \
        --inputbox "Servidores DNS Externos (Forwarders), separados por ponto e vírgula:" 8 65 "8.8.8.8; 1.1.1.1;") || return
    forwarders=$(echo "$forwarders" | tr -d '\r')

    local allowed_nets
    allowed_nets=$(whiptail_capture --title "Bind9 - Redes Permitidas" \
        --inputbox "Redes com permissão de consulta recursiva (allow-query):" 8 65 "any; 192.168.0.0/16; localhost;") || return
    allowed_nets=$(echo "$allowed_nets" | tr -d '\r')

    gauge_apt_install "Instalação do Bind9" "bind9" "bind9utils" "bind9-doc"

    local options_file="/etc/bind/named.conf.options"
    local backup_file=""
    if [[ -f "$options_file" ]]; then
        backup_file="${options_file}.bak.$(date +%F_%T)"
        cp "$options_file" "$backup_file"
    fi

    {
        echo 30
        echo "XXX\nDefinindo forwarders e políticas de cache recursivo...\nXXX"
        cat <<EOF > "$options_file"
options {
    directory "/var/cache/bind";

    forwarders {
        $forwarders
    };
    forward only;

    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { any; };
    allow-query { $allowed_nets };
    recursion yes;
};
EOF

        echo 70
        echo "XXX\nValidando sintaxe dos arquivos do Bind9 (named-checkconf)...\nXXX"
        named-checkconf /etc/bind/named.conf >> "$LOG_FILE" 2>&1

        echo 85
        echo "XXX\nReiniciando daemon do Bind9...\nXXX"
        systemctl enable bind9 >> "$LOG_FILE" 2>&1
        systemctl restart bind9 >> "$LOG_FILE" 2>&1

        echo 100
        echo "XXX\nServidor DNS Bind9 configurado!\nXXX"
        sleep 0.4
    } | whiptail --title "Aplicando Bind9" --gauge "Escrevendo arquivos de configuração..." 8 65 0

    show_service_result "bind9" "Servidor DNS (Bind9)" "$backup_file"
}

