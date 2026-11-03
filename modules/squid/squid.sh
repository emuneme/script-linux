#!/usr/bin/env bash
# ==============================================================================
# modules/squid/squid.sh - Proxy Squid com Cache e Blacklist de Domínios
# ==============================================================================

BLACKLIST_FILE="/etc/squid/bloqueados.txt"

manage_squid_menu() {
    local tmp_sq
    tmp_sq=$(mktemp /tmp/netmgr_sq.XXXXXX 2>/dev/null || echo "/tmp/netmgr_sq.$$.tmp")

    while true; do
        whiptail --title "Gerenciamento de Proxy Squid" \
            --menu "Escolha a operação desejada para o Squid:" 17 68 6 \
            "1" "Configurar / Inicializar Servidor Proxy Squid" \
            "2" "Adicionar Domínio à Lista de Bloqueio (Blacklist)" \
            "3" "Remover Domínio da Lista de Bloqueio" \
            "4" "Visualizar Lista de Domínios Bloqueados" \
            "5" "Recarregar Configurações (squid -k reconfigure)" \
            "6" "Retornar ao Menu Principal" 2>"$tmp_sq"

        local exit_status=$?
        local sq_opt
        sq_opt=$(cat "$tmp_sq" 2>/dev/null | tr -d '\r\n[:space:]')
        : > "$tmp_sq"

        [[ $exit_status -ne 0 || "$sq_opt" == "6" ]] && break

        case "$sq_opt" in
            1) configure_squid_proxy ;;
            2) squid_add_blocked_domain ;;
            3) squid_remove_blocked_domain ;;
            4) squid_view_blocked_domains ;;
            5) squid_reload_config ;;
        esac
    done
    rm -f "$tmp_sq"
}

# 1. Configuração Principal do Squid Proxy
configure_squid_proxy() {
    local proxy_port
    proxy_port=$(prompt_valid_port "Squid - Porta do Proxy" "Porta TCP de escuta do Squid:" "3128") || return

    local localnet
    localnet=$(prompt_valid_cidr "Squid - Rede Local Autorizada" "Sub-rede autorizada a navegar (ACL localnet):" "192.168.1.0/24") || return

    local cache_disk_mb
    cache_disk_mb=$(whiptail_capture --title "Squid - Cache em Disco" \
        --inputbox "Espaço em disco para cache em MB (ufs /var/spool/squid):" 8 60 "2048") || return
    cache_disk_mb=$(echo "$cache_disk_mb" | tr -d '[:space:]')

    local cache_ram_mb
    cache_ram_mb=$(whiptail_capture --title "Squid - Memória RAM para Cache" \
        --inputbox "Quantidade de memória RAM alocada para cache (MB):" 8 60 "256") || return
    cache_ram_mb=$(echo "$cache_ram_mb" | tr -d '[:space:]')

    local hostname
    hostname=$(whiptail_capture --title "Squid - Visible Hostname" \
        --inputbox "Nome visível do servidor proxy (visible_hostname):" 8 60 "proxy-corp.local") || return
    hostname=$(echo "$hostname" | tr -d '[:space:]')

    gauge_apt_install "Instalação do Squid Proxy" "squid"

    mkdir -p /etc/squid
    touch "$BLACKLIST_FILE"

    local conf_file="/etc/squid/squid.conf"
    local backup_file=""
    [[ -f "$conf_file" ]] && backup_file="${conf_file}.bak.$(date +%F_%T)" && cp "$conf_file" "$backup_file"

    {
        echo 20
        echo "XXX\nGerando novo arquivo /etc/squid/squid.conf...\nXXX"
        cat <<EOF > "$conf_file"
# squid.conf - Gerado automaticamente pelo Network Services Manager
visible_hostname $hostname

# ACLs de Portas Padrão e Seguras
acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 21          # ftp
acl Safe_ports port 443         # https
acl Safe_ports port 70          # gopher
acl Safe_ports port 210         # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280         # http-mgmt
acl Safe_ports port 488         # gss-http
acl Safe_ports port 591         # filemaker
acl Safe_ports port 777         # multiling http

# Bloqueio de conexões em portas não autorizadas
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# ACLs de Redes Locais e Localhost
acl localhost src 127.0.0.1/32 ::1
acl localnet src $localnet

# ACL de Filtro de Conteúdo / Blacklist de Domínios
acl sites_bloqueados dstdomain "$BLACKLIST_FILE"
http_access deny sites_bloqueados

# Regras de Controle de Acesso HTTP
http_access allow localhost manager
http_access deny manager
http_access allow localhost
http_access allow localnet
http_access deny all

# Porta de Escuta do Proxy
http_port $proxy_port

# Configuração de Cache
cache_mem ${cache_ram_mb} MB
maximum_object_size_in_memory 512 KB
cache_dir ufs /var/spool/squid ${cache_disk_mb} 16 256
minimum_object_size 0 KB
maximum_object_size 128 MB

# Logs de Acesso
access_log daemon:/var/log/squid/access.log squid
coredump_dir /var/spool/squid
EOF

        echo 60
        echo "XXX\nInicializando diretórios de spool do cache (squid -z)...\nXXX"
        systemctl stop squid >> "$LOG_FILE" 2>&1 || true
        squid -z >> "$LOG_FILE" 2>&1 || true

        echo 85
        echo "XXX\nHabilitando e reiniciando o serviço Squid...\nXXX"
        systemctl enable squid >> "$LOG_FILE" 2>&1
        systemctl restart squid >> "$LOG_FILE" 2>&1

        echo 100
        echo "XXX\nSquid Proxy configurado com sucesso!\nXXX"
        sleep 0.4
    } | whiptail --title "Aplicando Squid" --gauge "Configurando parâmetros e listas de controle..." 8 68 0

    show_service_result "squid" "Squid Proxy Server" "$backup_file"
}

# 2. Adicionar Domínio à Lista de Bloqueio
squid_add_blocked_domain() {
    mkdir -p /etc/squid
    touch "$BLACKLIST_FILE"

    local domain
    domain=$(whiptail_capture --title "Adicionar à Blacklist" \
        --inputbox "Informe o domínio a ser bloqueado (Ex: facebook.com ou .tiktok.com):" 8 60) || return
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]' | xargs)
    [[ -z "$domain" ]] && return

    # Garante que o domínio seja bloqueado inclusive com subdomínios se precedido de ponto
    if grep -Fxq "$domain" "$BLACKLIST_FILE" 2>/dev/null; then
        whiptail --title "Aviso" --msgbox "O domínio '$domain' já consta na lista de bloqueados." 8 55
        return
    fi

    echo "$domain" >> "$BLACKLIST_FILE"
    log_message "INFO" "Domínio '$domain' adicionado a $BLACKLIST_FILE"

    # Recarrega regras silenciosamente
    squid -k reconfigure >> "$LOG_FILE" 2>&1 || true
    whiptail --title "Domínio Bloqueado" \
        --msgbox "O domínio '$domain' foi adicionado à lista de bloqueio e o Squid foi recarregado!" 8 65
}

# 3. Remover Domínio da Lista de Bloqueio
squid_remove_blocked_domain() {
    if [[ ! -s "$BLACKLIST_FILE" ]]; then
        whiptail --title "Blacklist Vazia" --msgbox "Nenhum domínio cadastrado na lista de bloqueio." 8 55
        return
    fi

    local domains_menu=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        domains_menu+=("$line" "Bloqueado")
    done < "$BLACKLIST_FILE"

    local selected_domain
    selected_domain=$(whiptail_capture --title "Remover Domínio Bloqueado" \
        --menu "Selecione o domínio para liberar o acesso:" 16 65 6 "${domains_menu[@]}") || return
    selected_domain=$(echo "$selected_domain" | tr -d '[:space:]')
    [[ -z "$selected_domain" ]] && return

    # Remove o domínio do arquivo
    sed -i "/^${selected_domain}$/d" "$BLACKLIST_FILE"
    log_message "INFO" "Domínio '$selected_domain' removido de $BLACKLIST_FILE"

    squid -k reconfigure >> "$LOG_FILE" 2>&1 || true
    whiptail --title "Domínio Liberado" \
        --msgbox "O domínio '$selected_domain' foi removido da lista e liberado para navegação." 8 65
}

# 4. Visualizar Lista de Domínios Bloqueados
squid_view_blocked_domains() {
    if [[ ! -s "$BLACKLIST_FILE" ]]; then
        whiptail --title "Blacklist do Squid" --msgbox "A lista de domínios bloqueados está vazia no momento." 8 60
        return
    fi

    local content
    content=$(cat "$BLACKLIST_FILE")
    whiptail --title "Lista de Domínios Bloqueados (/etc/squid/bloqueados.txt)" \
        --scrolltext --msgbox "Domínios atualmente bloqueados:\n\n$content" 18 65
}

# 5. Recarregar Configurações do Squid
squid_reload_config() {
    if systemctl is-active --quiet squid; then
        squid -k reconfigure >> "$LOG_FILE" 2>&1
        whiptail --title "Squid" --msgbox "Configurações e ACLs recarregadas com sucesso no Squid (squid -k reconfigure)!" 8 65
    else
        whiptail --title "Squid Inativo" --msgbox "O serviço Squid não está em execução no momento." 8 55
    fi
}

