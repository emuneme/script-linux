#!/usr/bin/env bash
# ==============================================================================
# modules/dnsmasq/dnsmasq.sh - Servidor Integrado DHCP & DNS (Dnsmasq)
# ==============================================================================

configure_dnsmasq() {
    # 1. Resolução preventiva de conflito na porta 53
    check_and_resolve_port_53_conflict "Dnsmasq (DHCP & DNS)" || return

    # 2. Seleção de interface de rede
    local iface
    iface=$(select_network_interface "Selecione a interface LAN para o Dnsmasq:") || return
    verify_interface_ip_configured "$iface" "Dnsmasq DHCP" || return

    # 3. Coleta de parâmetros com validação estrita
    local range_start
    range_start=$(prompt_valid_ipv4 "Dnsmasq - DHCP Range Inicial" "Informe o IP inicial do pool DHCP:" "192.168.1.100") || return

    local range_end
    range_end=$(prompt_valid_ipv4 "Dnsmasq - DHCP Range Final" "Informe o IP final do pool DHCP:" "192.168.1.200") || return

    local netmask
    netmask=$(prompt_valid_ipv4 "Dnsmasq - Máscara de Sub-rede" "Informe a máscara da rede:" "255.255.255.0") || return

    local lease_time
    lease_time=$(whiptail --title "Dnsmasq - Tempo de Concessão (Lease)" \
        --inputbox "Tempo de concessão do lease (Ex: 12h, 24h, 7d):" 8 60 "12h" 3>&1 1>&2 2>&3) || return

    local gateway
    gateway=$(prompt_valid_ipv4 "Dnsmasq - Gateway Padrão" "Informe o IP do Gateway (Roteador):" "192.168.1.1") || return

    local dns_upstream
    dns_upstream=$(whiptail --title "Dnsmasq - Servidores DNS Externos" \
        --inputbox "Servidores DNS Upstream para resolução externa (separados por vírgula):" 8 65 "1.1.1.1, 8.8.8.8" 3>&1 1>&2 2>&3) || return

    local domain_name
    domain_name=$(whiptail --title "Dnsmasq - Nome do Domínio" \
        --inputbox "Domínio local da rede (Search Domain):" 8 60 "corp.local" 3>&1 1>&2 2>&3) || return

    # 4. Instalação do pacote
    gauge_apt_install "Instalação do Dnsmasq" "dnsmasq"

    local conf_file="/etc/dnsmasq.d/corp-dhcp-dns.conf"
    local backup_file=""
    if [[ -f "$conf_file" ]]; then
        backup_file="${conf_file}.bak.$(date +%F_%T)"
        cp "$conf_file" "$backup_file"
    fi

    # Formatar DNS upstream para o arquivo de configuração
    local upstream_lines=""
    IFS=',' read -ra ADDR <<< "$dns_upstream"
    for srv in "${ADDR[@]}"; do
        srv=$(echo "$srv" | xargs)
        [[ -n "$srv" ]] && upstream_lines+="server=$srv"$'\n'
    done

    # 5. Aplicação da configuração com Gauge
    {
        echo 25
        echo "XXX\nGravando arquivo de configuração em $conf_file...\nXXX"
        cat <<EOF > "$conf_file"
# Configuração corporativa do Dnsmasq gerada automaticamente
interface=$iface
bind-interfaces

# Configuração do Servidor DHCP
dhcp-range=$range_start,$range_end,$netmask,$lease_time
dhcp-option=option:router,$gateway
dhcp-option=option:dns-server,$gateway
dhcp-option=option:domain-name,$domain_name

# Configuração do Servidor DNS (Cache & Forwarders)
domain=$domain_name
expand-hosts
cache-size=1000
bogus-priv
domain-needed

$upstream_lines
EOF

        echo 60
        echo "XXX\nValidando sintaxe do arquivo de configuração (dnsmasq --test)...\nXXX"
        dnsmasq --test >> "$LOG_FILE" 2>&1

        echo 85
        echo "XXX\nHabilitando e reiniciando o serviço Dnsmasq...\nXXX"
        systemctl enable dnsmasq >> "$LOG_FILE" 2>&1
        systemctl restart dnsmasq >> "$LOG_FILE" 2>&1

        echo 100
        echo "XXX\nDnsmasq configurado com sucesso!\nXXX"
        sleep 0.4
    } | whiptail --title "Aplicando Dnsmasq" --gauge "Configurando DHCP e DNS integrados..." 8 68 0

    show_service_result "dnsmasq" "Dnsmasq (DHCP & DNS)" "$backup_file"
}

