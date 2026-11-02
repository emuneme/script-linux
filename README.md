# Guia de Uso: Gerenciador de Serviços de Rede Corporativos Linux

Este documento fornece a documentação completa, estrutura de diretórios e o guia passo a passo para operação e diagnóstico do **Network Services Manager**.

---

## ⚡ Instalação Rápida em 1 Linha (One-Liner)

Para instalar e executar diretamente a partir do repositório GitHub em qualquer servidor Debian ou Ubuntu:

```bash
curl -fsSL https://raw.githubusercontent.com/emuneme/script-linux/main/install.sh | sudo bash
```

> **O que o instalador faz automaticamente:**
> 1. Instala pré-requisitos essenciais (`git`, `curl`, `whiptail`).
> 2. Clona o repositório em `/opt/network-services-manager`.
> 3. Configura permissões e cria o comando global `/usr/local/bin/netmanager`.
> 4. Cria o atalho de execução interativa `sudo netmanager`.

Para abrir o gerenciador a qualquer momento no seu terminal:
```bash
sudo netmanager
```

## 1. Estrutura Modular do Projeto

O projeto foi desacoplado em uma arquitetura modular em camadas, onde cada serviço possui seu próprio diretório e ciclo de vida:

```text
Script_linux/
├── install.sh                    # Bootstrap / Instalador One-Liner via curl
├── network_services_manager.sh   # Entrypoint principal (Menu interativo)
├── README.md                     # Documentação de uso e arquitetura
├── lib/
│   ├── common.sh                 # Validações regex (IP/CIDR/Portas), Gauge e Logging
│   └── network_utils.sh          # Detecção de interfaces e mitigação de conflitos (porta 53)
└── modules/
    ├── dnsmasq/
    │   └── dnsmasq.sh            # Servidor integrado DHCP & DNS (Moderno e leve)
    ├── bind9/
    │   └── bind9.sh              # Servidor DNS recursivo com forwarders
    ├── samba/
    │   └── samba_ad.sh           # Active Directory Domain Controller (Samba 4 AD DC)
    ├── wireguard/
    │   └── wireguard.sh          # VPN WireGuard + Gerenciador Dinâmico de Peers e QR Code
    ├── squid/
    │   └── squid.sh              # Proxy com Cache e Blacklist (/etc/squid/bloqueados.txt)
    ├── ufw/
    │   └── ufw.sh                # Firewall UFW com perfis corporativos
    ├── netplan/
    │   └── netplan.sh            # Configuração de IP Estático persistente
    └── dashboard/
        └── dashboard.sh          # Painel de Status Geral em tempo real + últimas atividades
```

---

## 2. Execução Manual Local

Caso já tenha o repositório clonado localmente:

```bash
# Conceda permissão de execução a todos os scripts
chmod +x install.sh network_services_manager.sh lib/*.sh modules/*/*.sh

# Execute o gerenciador como root
sudo ./network_services_manager.sh
```

> **Log Central de Auditoria:** Todas as ações, comandos executados e erros são registrados em tempo real com timestamp em `/var/log/network_services_manager.log`.

---

## 3. Funcionalidades e Guias por Módulo

### 🔹 Módulo 1: Dnsmasq (DHCP & DNS Integrado)
Substitui stacks legadas (`isc-dhcp-server`) por uma solução moderna, unificada e extremamente veloz.
- **Prevenção de Conflito:** Detecta e resolve automaticamente o conflito da porta 53 com o `systemd-resolved`.
- **Validação de Interface:** Garante que a placa LAN possui IP atribuído antes de ligar o DHCP.
- **Entradas Validadas:** Range DHCP, máscara e gateway são validados por regex (rejeita octetos inválidos como `300`).
- **Arquivos:** Configuração gravada em `/etc/dnsmasq.d/corp-dhcp-dns.conf` e testada via `dnsmasq --test`.

---

### 🔹 Módulo 2: DNS Server (Bind9 - Cache & Forwarders)
Configura o tradicional Bind9 como resolvedor corporativo de alta performance.
- Desativa preventivamente o `DNSStubListener` conflitante se necessário.
- Valida sintaxe das zonas com `named-checkconf` antes de reiniciar o serviço.

---

### 🔹 Módulo 3: Active Directory Domain Controller (Samba 4 AD DC)
Transforma o servidor Linux em um Controlador de Domínio compatível com o Active Directory da Microsoft.
- Solicita Realm FQDN (ex: `CORP.LOCAL`), NetBIOS (ex: `CORP`) e senha administrativa em campos protegidos (`--passwordbox`) com confirmação obrigatória.
- Desativa e mascara daemons legados conflitantes (`smbd`, `nmbd`, `winbind`).
- Ajusta a infraestrutura do Kerberos (`/etc/krb5.conf`).

---

### 🔹 Módulo 4: VPN Server WireGuard (Com Gestão de Clientes)
Inclui um gerenciador dinâmico de conexões ponto a ponto:
1. **Configurar / Inicializar Servidor:** Configura porta UDP (`51820`), sub-rede do túnel (`10.0.0.1/24`), chaves do servidor e regras de masquerade/NAT no kernel.
2. **Adicionar Novo Cliente Peer:** Cria um novo usuário/dispositivo solicitando nome e IP. Adiciona o cliente sem reiniciar ou derrubar a VPN em execução (`wg set wg0 peer`).
3. **Listar Peers e Status:** Exibe tráfego, endpoints e tempos de handshake via `wg show`.
4. **Exibir QR Code:** Gera o QR Code ASCII no terminal para importação instantânea no aplicativo WireGuard (Android / iOS).
5. **Revogar Cliente Peer:** Desconecta e remove permanentemente o acesso de um peer selecionado.

---

### 🔹 Módulo 5: Proxy Squid (Com Blacklist de Domínios)
1. **Configurar Proxy:** Define porta (padrão `3128`), sub-rede local (`localnet`), limites de memória RAM e cache em disco em `/var/spool/squid`.
2. **Adicionar Domínio à Blacklist:** Adiciona sites como `facebook.com` ou `.tiktok.com` ao arquivo `/etc/squid/bloqueados.txt` e recarrega as ACLs automaticamente (`squid -k reconfigure`).
3. **Remover Domínio da Blacklist:** Menu interativo para selecionar e liberar o acesso a domínios bloqueados.
4. **Visualizar Lista de Bloqueios:** Exibe os sites restritos em uma janela com rolagem.

---

### 🔹 Módulo 6: Firewall (UFW)
- Submenu para ativar/desativar regras de firewall.
- Liberação pontual de portas com escolha de protocolo (TCP, UDP ou Ambos).
- **Perfis Corporativos em 1 Clique:** Libera SSH (`22`), DHCP (`67`), DNS (`53`), WireGuard (`51820`), Squid (`3128`) e Samba AD (`88, 135, 138, 139, 389, 445, 464, 636, 3268, 3269`).
- Visualização de regras ativas numeradas (`ufw status numbered`).

---

### 🔹 Módulo 7: Configuração de IP Estático (Netplan)
- Seleção visual de placas de rede ativas (excluindo loopback).
- Validação estrita de IP em formato CIDR e gateway padrão.
- Aplicação silenciosa e segura com `netplan apply` e exibição do IP atualizado.

---

### 🔹 Módulo 8: Painel de Status Geral dos Serviços & Logs
Apresenta em uma única tela o estado em tempo real de todos os daemons (`Dnsmasq`, `Bind9`, `Samba`, `WireGuard`, `Squid`, `UFW`), tabela de endereçamento das placas e os últimos registros gravados em `/var/log/network_services_manager.log`.

---

## 4. Diagnóstico e Resolução de Problemas

Se qualquer serviço falhar, o script oferecerá a restauração imediata do arquivo de backup anterior. Para diagnóstico aprofundado:

```bash
# Ver os logs completos do gerenciador
sudo tail -f /var/log/network_services_manager.log

# Diagnóstico de serviços específicos:
sudo journalctl -xeu dnsmasq
sudo journalctl -xeu bind9
sudo journalctl -xeu samba-ad-dc
sudo journalctl -xeu wg-quick@wg0
sudo journalctl -xeu squid
sudo ufw status verbose
```
