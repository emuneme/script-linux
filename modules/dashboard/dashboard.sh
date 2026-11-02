#!/usr/bin/env bash
# ==============================================================================
# modules/dashboard/dashboard.sh - Painel Geral de Monitoramento e Logs
# ==============================================================================

show_general_status_dashboard() {
    local dnsmasq_status bind9_status samba_status wg_status squid_status ufw_status

    systemctl is-active --quiet dnsmasq && dnsmasq_status="[ ATIVO / OK ]" || dnsmasq_status="[ INATIVO / OFF ]"
    (systemctl is-active --quiet bind9 || systemctl is-active --quiet named) && bind9_status="[ ATIVO / OK ]" || bind9_status="[ INATIVO / OFF ]"
    systemctl is-active --quiet samba-ad-dc && samba_status="[ ATIVO / OK ]" || samba_status="[ INATIVO / OFF ]"
    systemctl is-active --quiet wg-quick@wg0 && wg_status="[ ATIVO / OK ]" || wg_status="[ INATIVO / OFF ]"
    systemctl is-active --quiet squid && squid_status="[ ATIVO / OK ]" || squid_status="[ INATIVO / OFF ]"
    
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -qw "active"; then
        ufw_status="[ ATIVO / OK ]"
    else
        ufw_status="[ INATIVO / OFF ]"
    fi

    local interfaces_info
    interfaces_info=$(ip -4 -o addr show | grep -v ' lo ' | awk '{printf "  • %-10s : %s\n", $2, $4}')

    local last_logs
    if [[ -f "$LOG_FILE" ]]; then
        last_logs=$(tail -n 6 "$LOG_FILE")
    else
        last_logs="Nenhum registro de log encontrado."
    fi

    local report
    report="==============================================================
            PAINEL DE STATUS DE SERVIÇOS DE REDE
==============================================================

  1. Dnsmasq (DHCP & DNS Leve)     : $dnsmasq_status
  2. Bind9 (DNS Forwarders/Cache)  : $bind9_status
  3. Samba 4 Active Directory DC   : $samba_status
  4. VPN Server (WireGuard)        : $wg_status
  5. Proxy Server (Squid)          : $squid_status
  6. Firewall Local (UFW)          : $ufw_status

--------------------------------------------------------------
  ENDEREÇAMENTO IP DAS INTERFACES:
--------------------------------------------------------------
${interfaces_info:-  Nenhuma interface de rede IPv4 detectada}

--------------------------------------------------------------
  ÚLTIMAS ATIVIDADES NO LOG ($LOG_FILE):
--------------------------------------------------------------
$last_logs

==============================================================
Pressione [Enter] ou [Esc] para retornar ao Menu Principal."

    whiptail --title "Painel Geral de Monitoramento" --scrolltext --msgbox "$report" 24 72
}

