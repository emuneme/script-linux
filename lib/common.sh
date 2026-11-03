#!/usr/bin/env bash
# ==============================================================================
# lib/common.sh - Funções Utilitárias, Logging, Validações e UI Whiptail
# ==============================================================================

LOG_FILE="/var/log/network_services_manager.log"
touch "$LOG_FILE" 2>/dev/null || true
chmod 640 "$LOG_FILE" 2>/dev/null || true

# Registrador de Logs do Sistema
log_message() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
}

# Execução de comando com indicador Gauge
run_gauge() {
    local title="$1"
    local message="$2"
    shift 2
    local cmd=("$@")

    log_message "INFO" "Iniciando tarefa: $title - ${cmd[*]}"

    {
        echo 15
        echo "XXX\n[1/4] Inicializando operação...\nXXX"
        sleep 0.3
        echo 40
        echo "XXX\n[2/4] Executando comandos do sistema...\nXXX"
        
        "${cmd[@]}" >> "$LOG_FILE" 2>&1
        local exit_code=$?

        echo 80
        echo "XXX\n[3/4] Validando aplicação das alterações...\nXXX"
        sleep 0.3
        echo 100
        echo "XXX\n[4/4] Operação concluída!\nXXX"
        sleep 0.3

        if [[ $exit_code -eq 0 ]]; then
            log_message "SUCCESS" "Tarefa '$title' concluída com êxito."
        else
            log_message "ERROR" "Tarefa '$title' falhou com código de saída $exit_code."
        fi
        return "$exit_code"
    } | whiptail --title "$title" --gauge "$message" 8 65 0
}

# Instalador de Pacotes via APT com Gauge
gauge_apt_install() {
    local title="$1"
    shift
    local packages=("$@")

    log_message "INFO" "Instalação de pacotes solicitada: ${packages[*]}"

    {
        echo 15
        echo "XXX\nAtualizando repositórios de pacotes (apt update)...\nXXX"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >> "$LOG_FILE" 2>&1

        echo 50
        echo "XXX\nBaixando e instalando pacotes: ${packages[*]}...\nXXX"
        apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${packages[@]}" >> "$LOG_FILE" 2>&1
        local status=$?

        echo 90
        echo "XXX\nFinalizando configurações de dependências...\nXXX"
        sleep 0.3
        echo 100
        echo "XXX\nPacotes instalados!\nXXX"
        sleep 0.3
        
        if [[ $status -eq 0 ]]; then
            log_message "SUCCESS" "Pacotes ${packages[*]} instalados com sucesso."
        else
            log_message "ERROR" "Falha na instalação dos pacotes ${packages[*]} (código $status)."
        fi
        return $status
    } | whiptail --title "$title" --gauge "Processando gerenciador de pacotes APT..." 8 68 0
}

# ------------------------------------------------------------------------------
# Funções de Validação de Dados (Regex e Lógica)
# ------------------------------------------------------------------------------

validate_ipv4() {
    local ip="$1"
    local IFS='.'
    read -r -a octets <<< "$ip"
    [[ ${#octets[@]} -ne 4 ]] && return 1

    for octet in "${octets[@]}"; do
        [[ ! "$octet" =~ ^[0-9]+$ ]] && return 1
        (( octet < 0 || octet > 255 )) && return 1
        # Rejeitar zeros à esquerda não intencionais (ex: 01)
        [[ ${#octet} -gt 1 && ${octet:0:1} == '0' ]] && return 1
    done
    return 0
}

validate_cidr() {
    local cidr="$1"
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"

    [[ "$cidr" != *"/"* ]] && return 1
    validate_ipv4 "$ip" || return 1
    [[ ! "$prefix" =~ ^[0-9]+$ ]] && return 1
    (( prefix < 0 || prefix > 32 )) && return 1
    return 0
}

validate_port() {
    local port="$1"
    [[ ! "$port" =~ ^[0-9]+$ ]] && return 1
    (( port >= 1 && port <= 65535 )) && return 0
    return 1
}

# Helper seguro para captura de dados de whiptail sem conflito de descritores (3>&1)
whiptail_capture() {
    local tmp_cap
    tmp_cap=$(mktemp /tmp/netmgr_cap.XXXXXX 2>/dev/null || echo "/tmp/netmgr_cap.$$.$RANDOM.tmp")
    whiptail "$@" 1>&2 2>"$tmp_cap"
    local status=$?
    local content
    content=$(cat "$tmp_cap" 2>/dev/null | tr -d '\r')
    rm -f "$tmp_cap"
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi
    echo "$content"
    return 0
}

# Prompts Interativos de Input com Loop e Validação Estrita
prompt_valid_ipv4() {
    local title="$1"
    local msg="$2"
    local default_val="$3"
    local input

    while true; do
        input=$(whiptail_capture --title "$title" --inputbox "$msg" 8 62 "$default_val") || return 1
        input=$(echo "$input" | tr -d '[:space:]')

        if validate_ipv4 "$input"; then
            echo "$input"
            return 0
        fi
        whiptail --title "Entrada Inválida" \
            --msgbox "O endereço IPv4 informado '$input' não é válido!\nFormato esperado: X.X.X.X (octetos de 0 a 255)." 8 60 >&2
    done
}

prompt_valid_cidr() {
    local title="$1"
    local msg="$2"
    local default_val="$3"
    local input

    while true; do
        input=$(whiptail_capture --title "$title" --inputbox "$msg" 8 65 "$default_val") || return 1
        input=$(echo "$input" | tr -d '[:space:]')

        if validate_cidr "$input"; then
            echo "$input"
            return 0
        fi
        whiptail --title "Entrada Inválida" \
            --msgbox "O endereço CIDR '$input' não é válido!\nFormato esperado: X.X.X.X/Mascara (Ex: 192.168.1.0/24)." 8 60 >&2
    done
}

prompt_valid_port() {
    local title="$1"
    local msg="$2"
    local default_val="$3"
    local input

    while true; do
        input=$(whiptail_capture --title "$title" --inputbox "$msg" 8 60 "$default_val") || return 1
        input=$(echo "$input" | tr -d '[:space:]')

        if validate_port "$input"; then
            echo "$input"
            return 0
        fi
        whiptail --title "Entrada Inválida" \
            --msgbox "A porta '$input' é inválida!\nInforme um número inteiro entre 1 e 65535." 8 55 >&2
    done
}

# Exibição de Status de Serviço com Opção de Rollback Automático
show_service_result() {
    local service_name="$1"
    local friendly_name="$2"
    local backup_file="${3:-}"

    if systemctl is-active --quiet "$service_name"; then
        log_message "SUCCESS" "Serviço $service_name está ativo e operacional."
        whiptail --title "Sucesso - $friendly_name" \
            --msgbox "O serviço '$service_name' foi configurado e está ATIVO e OPERANTE no sistema!\n\nStatus: [ OK ]" 10 65
    else
        log_message "ERROR" "Serviço $service_name falhou ao inicializar."
        local err_msg="O serviço '$service_name' NÃO está em execução.\n\nInstrução de diagnóstico:\nExecute no terminal:\njournalctl -xeu $service_name\nLog detalhado em: $LOG_FILE"
        
        if [[ -n "$backup_file" && -f "$backup_file" ]]; then
            err_msg+="\n\nDeseja restaurar a configuração anterior de backup?"
            if whiptail --title "Falha no Serviço - Rollback" --yesno "$err_msg" 14 68; then
                local target_file="${backup_file%.bak.*}"
                cp "$backup_file" "$target_file" 2>/dev/null || true
                systemctl restart "$service_name" >/dev/null 2>&1 || true
                log_message "WARN" "Rollback executado para $target_file a partir de $backup_file."
                whiptail --title "Rollback Concluído" \
                    --msgbox "A configuração anterior foi restaurada com sucesso a partir de:\n$backup_file" 9 65
            fi
        else
            whiptail --title "Atenção - Falha no Serviço" --msgbox "$err_msg" 13 65
        fi
    fi
}

