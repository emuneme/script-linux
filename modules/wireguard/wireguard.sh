#!/usr/bin/env bash
# ==============================================================================
# modules/wireguard/wireguard.sh - VPN WireGuard com Gestão Dinâmica de Clientes
# ==============================================================================

manage_wireguard_menu() {
    local tmp_wg
    tmp_wg=$(mktemp /tmp/netmgr_wg.XXXXXX 2>/dev/null || echo "/tmp/netmgr_wg.$$.tmp")

    while true; do
        whiptail --title "Gerenciamento de VPN WireGuard" \
            --menu "Escolha a operação desejada para o WireGuard:" 17 68 6 \
            "1" "Configurar / Inicializar Servidor WireGuard" \
            "2" "Adicionar Novo Cliente Peer (Novo Usuário)" \
            "3" "Listar Peers e Status da VPN (wg show)" \
            "4" "Exibir QR Code de Configuração de um Cliente" \
            "5" "Revogar / Excluir Cliente Peer" \
            "6" "Retornar ao Menu Principal" 2>"$tmp_wg"

        local exit_status=$?
        local wg_opt
        wg_opt=$(cat "$tmp_wg" 2>/dev/null | tr -d '\r\n[:space:]')
        : > "$tmp_wg"

        [[ $exit_status -ne 0 || "$wg_opt" == "6" ]] && break

        case "$wg_opt" in
            1) wg_setup_server ;;
            2) wg_add_peer_client ;;
            3) wg_list_peers_status ;;
            4) wg_show_client_qr ;;
            5) wg_revoke_peer_client ;;
        esac
    done
    rm -f "$tmp_wg"
}

# 1. Configuração Inicial do Servidor WireGuard
wg_setup_server() {
    local wan_iface
    wan_iface=$(select_network_interface "Selecione a interface WAN de saída para NAT:") || return

    local listen_port
    listen_port=$(prompt_valid_port "WireGuard - Porta de Escuta" "Porta UDP de escuta do servidor:" "51820") || return

    local server_tunnel_ip
    server_tunnel_ip=$(prompt_valid_cidr "WireGuard - IP do Servidor" "Sub-rede / IP do servidor na VPN:" "10.0.0.1/24") || return

    gauge_apt_install "Instalação do WireGuard" "wireguard" "iptables" "iptables-persistent" "qrencode"

    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard

    local conf_file="/etc/wireguard/wg0.conf"
    local backup_file=""
    [[ -f "$conf_file" ]] && backup_file="${conf_file}.bak.$(date +%F_%T)" && cp "$conf_file" "$backup_file"

    {
        echo 20
        echo "XXX\nHabilitando net.ipv4.ip_forward=1 no Kernel...\nXXX"
        sysctl -w net.ipv4.ip_forward=1 >> "$LOG_FILE" 2>&1
        if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        fi

        echo 45
        echo "XXX\nGerando chaves criptográficas do servidor...\nXXX"
        local srv_priv srv_pub
        srv_priv=$(wg genkey)
        srv_pub=$(echo "$srv_priv" | wg pubkey)

        echo "$srv_priv" > /etc/wireguard/server_private.key
        echo "$srv_pub" > /etc/wireguard/server_public.key
        chmod 600 /etc/wireguard/server_private.key

        echo 70
        echo "XXX\nGerando arquivo de configuração $conf_file...\nXXX"
        cat <<EOF > "$conf_file"
[Interface]
Address = $server_tunnel_ip
ListenPort = $listen_port
PrivateKey = $srv_priv
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $wan_iface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $wan_iface -j MASQUERADE

# PEERS CADASTRADOS DINAMICAMENTE
EOF
        chmod 600 "$conf_file"

        echo 85
        echo "XXX\nIniciando interface WireGuard wg0...\nXXX"
        systemctl enable wg-quick@wg0 >> "$LOG_FILE" 2>&1
        systemctl restart wg-quick@wg0 >> "$LOG_FILE" 2>&1

        echo 100
        echo "XXX\nServidor WireGuard configurado!\nXXX"
        sleep 0.4
    } | whiptail --title "Provisionamento WireGuard" --gauge "Configurando infraestrutura de VPN..." 8 65 0

    show_service_result "wg-quick@wg0" "WireGuard VPN Server" "$backup_file"
}

# 2. Adicionar Novo Cliente Peer (Usuário)
wg_add_peer_client() {
    if ! systemctl is-active --quiet wg-quick@wg0; then
        whiptail --title "Atenção" --msgbox "O servidor WireGuard precisa estar configurado e ativo antes de adicionar clientes." 8 65
        return
    fi

    local client_name
    client_name=$(whiptail_capture --title "Novo Peer - Identificador" \
        --inputbox "Nome/Identificador do cliente (Ex: joao-laptop, diretoria):" 8 60 "cliente1") || return
    # Sanitiza o nome para evitar caracteres especiais
    client_name=$(echo "$client_name" | tr -cd '[:alnum:]_-')
    [[ -z "$client_name" ]] && return

    local client_ip
    client_ip=$(prompt_valid_cidr "Novo Peer - Endereço IP" "IP do cliente no túnel (com /32):" "10.0.0.2/32") || return

    local client_dns
    client_dns=$(whiptail_capture --title "Novo Peer - DNS" \
        --inputbox "Servidor DNS entregue ao cliente:" 8 60 "1.1.1.1") || return
    client_dns=$(echo "$client_dns" | tr -d '[:space:]')

    # Gera chaves do cliente
    local cli_priv cli_pub srv_pub listen_port srv_ip
    cli_priv=$(wg genkey)
    cli_pub=$(echo "$cli_priv" | wg pubkey)
    srv_pub=$(cat /etc/wireguard/server_public.key)
    listen_port=$(grep "^ListenPort" /etc/wireguard/wg0.conf | awk '{print $3}')

    # Tenta descobrir o IP WAN/Público da máquina
    local endpoint_ip
    endpoint_ip=$(curl -s -m 3 ifconfig.me 2>/dev/null || ip -4 -o addr show | grep -v ' lo ' | awk '{print $4}' | cut -d'/' -f1 | head -n1)
    [[ -z "$endpoint_ip" ]] && endpoint_ip="IP_PUBLICO_DO_SERVIDOR"

    # 1. Adiciona peer ao arquivo de configuração persistente
    cat <<EOF >> /etc/wireguard/wg0.conf

# Client: $client_name
[Peer]
PublicKey = $cli_pub
AllowedIPs = $client_ip
EOF

    # 2. Adiciona ao runtime sem derrubar conexões ativas
    wg set wg0 peer "$cli_pub" allowed-ips "$client_ip" 2>/dev/null || true

    # 3. Cria arquivo de configuração do cliente
    local client_file="/root/wireguard-${client_name}.conf"
    cat <<EOF > "$client_file"
[Interface]
PrivateKey = $cli_priv
Address = $client_ip
DNS = $client_dns

[Peer]
PublicKey = $srv_pub
Endpoint = ${endpoint_ip}:${listen_port}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    chmod 600 "$client_file"

    log_message "SUCCESS" "Peer '$client_name' adicionado ($client_ip). Arquivo: $client_file"
    whiptail --title "Peer Adicionado com Sucesso" \
        --msgbox "Cliente '$client_name' adicionado à VPN!\n\nArquivo de Perfil salvo em:\n$client_file\n\nVocê pode transferir este arquivo ou exibir o QR Code no menu." 12 68
}

# 3. Listar Peers Ativos e Tráfego
wg_list_peers_status() {
    local status_output
    if command -v wg >/dev/null 2>&1; then
        status_output=$(wg show 2>&1)
    else
        status_output="Comando 'wg' não encontrado no sistema."
    fi
    whiptail --title "WireGuard - Peers Conectados e Tráfego" --scrolltext --msgbox "$status_output" 19 72
}

# 4. Exibir QR Code de um Cliente no Terminal
wg_show_client_qr() {
    local conf_files=()
    for f in /root/wireguard-*.conf; do
        [[ -f "$f" ]] && conf_files+=("$f" "$(basename "$f")")
    done

    if [[ ${#conf_files[@]} -eq 0 ]]; then
        whiptail --title "QR Code" --msgbox "Nenhum arquivo de configuração de cliente (/root/wireguard-*.conf) encontrado." 8 65
        return
    fi

    local selected_file
    selected_file=$(whiptail_capture --title "Selecionar Cliente para QR Code" \
        --menu "Escolha o perfil do cliente desejado:" 15 65 5 "${conf_files[@]}") || return
    selected_file=$(echo "$selected_file" | tr -d '[:space:]')
    [[ -z "$selected_file" ]] && return

    # Renderiza o QR Code em tela cheia com pausa
    clear
    echo "======================================================================"
    echo " QR CODE DE CONEXÃO WIREGUARD - $(basename "$selected_file")"
    echo " Aponte a câmera do aplicativo WireGuard (Android / iOS) abaixo:"
    echo "======================================================================"
    qrencode -t ansiutf8 < "$selected_file"
    echo "======================================================================"
    read -rp "Pressione [ENTER] para retornar ao menu..."
}

# 5. Revogar / Excluir Cliente Peer
wg_revoke_peer_client() {
    local conf_files=()
    for f in /root/wireguard-*.conf; do
        [[ -f "$f" ]] && conf_files+=("$f" "$(basename "$f")")
    done

    if [[ ${#conf_files[@]} -eq 0 ]]; then
        whiptail --title "Revogar Peer" --msgbox "Nenhum cliente disponível para revogação." 8 50
        return
    fi

    local selected_file
    selected_file=$(whiptail_capture --title "Revogar Cliente Peer" \
        --menu "Selecione o cliente que deseja remover permanentemente:" 15 65 5 "${conf_files[@]}") || return
    selected_file=$(echo "$selected_file" | tr -d '[:space:]')
    [[ -z "$selected_file" ]] && return

    if whiptail --title "Confirmar Exclusão" --yesno "Tem certeza que deseja revogar o acesso de $(basename "$selected_file")?" 8 60; then
        # Extrai chave pública do arquivo do cliente
        local cli_priv
        cli_priv=$(grep "^PrivateKey" "$selected_file" | awk '{print $3}')
        if [[ -n "$cli_priv" ]]; then
            local cli_pub
            cli_pub=$(echo "$cli_priv" | wg pubkey 2>/dev/null)
            [[ -n "$cli_pub" ]] && wg set wg0 peer "$cli_pub" remove 2>/dev/null || true
        fi

        # Remove bloco do cliente em /etc/wireguard/wg0.conf
        local client_base
        client_base=$(basename "$selected_file" .conf | sed 's/^wireguard-//')
        sed -i "/# Client: $client_base/,+4d" /etc/wireguard/wg0.conf 2>/dev/null || true

        # Arquiva ou remove o arquivo de configuração
        rm -f "$selected_file"
        log_message "WARN" "Cliente WireGuard '$client_base' revogado e removido."
        whiptail --title "Peer Revogado" --msgbox "O cliente '$client_base' foi desconectado e removido das configurações da VPN." 8 60
    fi
}

