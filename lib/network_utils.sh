#!/usr/bin/env bash
# ==============================================================================
# lib/network_utils.sh - Detecção de Interfaces, Conflitos de Portas e Checagens
# ==============================================================================

# Seleção Dinâmica de Interface de Rede
select_network_interface() {
    local prompt_msg="${1:-Selecione a interface de rede:}"
    local ifaces_menu=()
    local iface
    local ip_addr

    while IFS= read -r iface; do
        [[ -z "$iface" ]] && continue
        ip_addr=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | head -n1)
        [[ -z "$ip_addr" ]] && ip_addr="Sem IP / Desconectada"
        ifaces_menu+=("$iface" "($ip_addr)")
    done < <(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | cut -d'@' -f1)

    if [[ ${#ifaces_menu[@]} -eq 0 ]]; then
        whiptail --title "Erro de Rede" --msgbox "Nenhuma placa de rede ativa encontrada no sistema (exceto 'lo')." 8 60 >&2
        return 1
    fi

    local selected_iface
    selected_iface=$(whiptail --title "Detecção de Placas de Rede" \
        --menu "$prompt_msg" 15 66 5 "${ifaces_menu[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 || -z "$selected_iface" ]]; then
        return 1
    fi

    echo "$selected_iface"
    return 0
}

# Verificação e Resolução de Conflito na Porta 53 (systemd-resolved)
check_and_resolve_port_53_conflict() {
    local target_service="${1:-serviço DNS}"
    
    # Verifica se há processo escutando na porta 53
    if ss -tulpn 2>/dev/null | grep -q ':53 '; then
        local process_name
        process_name=$(ss -tulpn 2>/dev/null | grep ':53 ' | awk '{print $NF}' | head -n1 | tr -d '"')
        
        log_message "WARN" "Conflito detectado na porta 53: $process_name. Alvo: $target_service"

        local prompt="A porta 53 já está em uso no sistema:\n$process_name\n\nIsso pode impedir o funcionamento do $target_service.\nDeseja que o gerenciador desative o DNSStubListener e libere a porta 53 automaticamente agora?"
        
        if whiptail --title "Conflito na Porta 53" --yesno "$prompt" 14 66; then
            {
                echo 25
                echo "XXX\nAjustando /etc/systemd/resolved.conf...\nXXX"
                mkdir -p /etc/systemd/resolved.conf.d/
                cat <<EOF > /etc/systemd/resolved.conf.d/disable-stub.conf
[Resolve]
DNS=8.8.8.8 1.1.1.1
DNSStubListener=no
EOF

                echo 60
                echo "XXX\nAplicando novo symlink para /etc/resolv.conf...\nXXX"
                rm -f /etc/resolv.conf
                ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf

                echo 85
                echo "XXX\nReiniciando systemd-resolved e liberando daemons conflitantes...\nXXX"
                systemctl restart systemd-resolved >/dev/null 2>&1 || true

                # Se o alvo for Dnsmasq/Samba, para Bind9 caso ativo
                if [[ "$target_service" =~ Dnsmasq|Samba ]]; then
                    systemctl stop bind9 named >/dev/null 2>&1 || true
                    systemctl disable bind9 named >/dev/null 2>&1 || true
                fi
                # Se o alvo for Bind9/Samba, para Dnsmasq caso ativo
                if [[ "$target_service" =~ Bind9|Samba ]]; then
                    systemctl stop dnsmasq >/dev/null 2>&1 || true
                    systemctl disable dnsmasq >/dev/null 2>&1 || true
                fi

                echo 100
                echo "XXX\nPorta 53 liberada com sucesso!\nXXX"
                sleep 0.5
            } | whiptail --title "Resolução de Conflito" --gauge "Liberando porta 53..." 8 65 0

            log_message "SUCCESS" "DNSStubListener desativado em systemd-resolved com sucesso."
            return 0
        else
            log_message "WARN" "Usuário optou por ignorar o conflito da porta 53."
            return 0
        fi
    fi
    return 0
}

# Verifica se a interface possui IP estático/ativo antes de vincular serviços como DHCP
verify_interface_ip_configured() {
    local iface="$1"
    local service_name="$2"

    local current_ip
    current_ip=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | head -n1)

    if [[ -z "$current_ip" ]]; then
        local msg="A interface '$iface' NÃO possui um endereço IP IPv4 configurado!\n\nServiços como $service_name falharão ao inicializar sem um IP na mesma sub-rede.\n\nRecomendação: Configure primeiro um IP Estático (Módulo Netplan).\n\nDeseja continuar mesmo assim?"
        if ! whiptail --title "Aviso de Pré-requisito" --yesno "$msg" 13 65; then
            return 1
        fi
    fi
    return 0
}

