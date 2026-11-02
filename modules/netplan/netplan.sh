#!/usr/bin/env bash
# ==============================================================================
# modules/netplan/netplan.sh - Configuração de Endereçamento IP Estático (Netplan)
# ==============================================================================

configure_static_ip_netplan() {
    local iface
    iface=$(select_network_interface "Selecione a interface para aplicar IP Estático:") || return

    local ip_cidr
    ip_cidr=$(prompt_valid_cidr "Netplan - Endereço IP e Máscara" \
        "Informe o endereço IP com a notação CIDR (Ex: 192.168.1.50/24):" "192.168.1.50/24") || return

    local gateway
    gateway=$(prompt_valid_ipv4 "Netplan - Gateway" \
        "Informe o IP do Gateway padrão (Roteador):" "192.168.1.1") || return

    local dns_list
    dns_list=$(whiptail --title "Netplan - Servidores DNS" \
        --inputbox "Informe os DNSs (separados por vírgula):" 8 60 "1.1.1.1, 8.8.8.8" 3>&1 1>&2 2>&3) || return

    # Formata a lista de DNS para a sintaxe YAML [ "1.1.1.1", "8.8.8.8" ]
    local formatted_dns
    formatted_dns=$(echo "$dns_list" | awk -F',' '{for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/, "", $i); printf "\"%s\"%s", $i, (i==NF?"":", ")}}')

    local netplan_file="/etc/netplan/99-corp-static-${iface}.yaml"
    mkdir -p /etc/netplan

    local backup_file=""
    [[ -f "$netplan_file" ]] && backup_file="${netplan_file}.bak.$(date +%F_%T)" && cp "$netplan_file" "$backup_file"

    {
        echo 30
        echo "XXX\nGerando arquivo de configuração $netplan_file...\nXXX"
        cat <<EOF > "$netplan_file"
network:
  version: 2
  renderer: networkd
  ethernets:
    $iface:
      dhcp4: false
      dhcp6: false
      addresses:
        - $ip_cidr
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses: [$formatted_dns]
EOF
        chmod 600 "$netplan_file"

        echo 70
        echo "XXX\nAplicando configurações com 'netplan apply'...\nXXX"
        netplan apply >> "$LOG_FILE" 2>&1
        local apply_status=$?

        echo 100
        echo "XXX\nConfiguração aplicada com sucesso!\nXXX"
        sleep 0.4
        return "$apply_status"
    } | whiptail --title "Aplicando Netplan" --gauge "Gravando parâmetros de rede estática..." 8 65 0

    local current_ip
    current_ip=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | head -n1)

    if [[ -n "$current_ip" ]]; then
        log_message "SUCCESS" "IP Estático aplicado com sucesso na interface $iface: $current_ip"
        whiptail --title "Netplan - Concluído" \
            --msgbox "Configuração estática gravada e aplicada na interface $iface!\n\nArquivo: $netplan_file\nEndereçamento atual: $current_ip" 12 65
    else
        log_message "ERROR" "Falha ao verificar IP da interface $iface após netplan apply."
        whiptail --title "Atenção" \
            --msgbox "O Netplan foi aplicado, mas não foi detectado IP ativo na interface $iface.\nVerifique logs em: $LOG_FILE" 10 65
    fi
}

