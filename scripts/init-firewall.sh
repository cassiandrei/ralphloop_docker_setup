#!/bin/bash
# Firewall initialization - permite apenas domínios essenciais
# Baseado no devcontainer oficial da Anthropic

set -e

echo "🔒 Inicializando firewall com whitelist de domínios..."

# Domínios permitidos (essenciais para Claude Code e desenvolvimento)
ALLOWED_DOMAINS=(
    # Claude/Anthropic
    "api.anthropic.com"
    "claude.ai"
    "statsig.anthropic.com"
    "sentry.io"
    
    # Package managers
    "registry.npmjs.org"
    "pypi.org"
    "files.pythonhosted.org"
    
    # Git
    "github.com"
    "gitlab.com"
    "bitbucket.org"
    
    # DNS (Cloudflare e Google)
    "1.1.1.1"
    "8.8.8.8"
)

# Criar ipset para IPs permitidos
sudo ipset create allowed_ips hash:ip -exist
sudo ipset flush allowed_ips

# Resolver domínios e adicionar IPs ao ipset
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "  Resolvendo: $domain"
    # Tenta resolver, ignora se falhar (alguns são IPs diretos)
    ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' || echo "$domain")
    for ip in $ips; do
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            sudo ipset add allowed_ips "$ip" -exist
        fi
    done
done

# Configurar iptables
# Política padrão: bloquear saída
sudo iptables -P OUTPUT DROP

# Permitir loopback (localhost)
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Permitir conexões estabelecidas
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Permitir DNS (porta 53 UDP/TCP)
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Permitir IPs na whitelist (HTTP/HTTPS)
sudo iptables -A OUTPUT -m set --match-set allowed_ips dst -p tcp --dport 80 -j ACCEPT
sudo iptables -A OUTPUT -m set --match-set allowed_ips dst -p tcp --dport 443 -j ACCEPT

# Permitir SSH para git
sudo iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Log de conexões bloqueadas (opcional, pode gerar muito log)
# sudo iptables -A OUTPUT -j LOG --log-prefix "BLOCKED: " --log-level 4

echo "✅ Firewall configurado!"
echo "   Domínios permitidos: ${#ALLOWED_DOMAINS[@]}"

# Verificar regras
echo ""
echo "📋 Regras ativas:"
sudo iptables -L OUTPUT -n --line-numbers | head -20
