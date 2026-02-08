#!/bin/bash
# Entrypoint - configura ambiente e inicia

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Ralph Loop Docker Environment                      ║"
echo "║           Claude Code com assinatura Max                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Verificar se o token OAuth está configurado
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "⚠️  CLAUDE_CODE_OAUTH_TOKEN não definido!"
    echo ""
    echo "Para obter o token:"
    echo "  1. No seu host, execute: claude setup-token"
    echo "  2. Copie o token gerado (sk-ant-oat01-...)"
    echo "  3. Execute o container com: -e CLAUDE_CODE_OAUTH_TOKEN=seu-token"
    echo ""
    echo "Ou faça login interativo agora com: claude login"
    echo ""
else
    echo "✓ Token OAuth configurado"
    # Criar arquivo de credenciais se não existir
    if [ ! -f /home/claude/.claude/.credentials.json ]; then
        mkdir -p /home/claude/.claude
        cat > /home/claude/.claude/.credentials.json << EOF
{
  "claudeAiOauth": {
    "accessToken": "$CLAUDE_CODE_OAUTH_TOKEN"
  }
}
EOF
        echo "✓ Credenciais configuradas"
    fi
fi

# Inicializar firewall (requer capabilities)
if [ "${ENABLE_FIREWALL:-true}" = "true" ]; then
    if [ -x /usr/local/bin/init-firewall.sh ]; then
        echo ""
        echo "Configurando firewall..."
        /usr/local/bin/init-firewall.sh 2>/dev/null || {
            echo "⚠️  Firewall não pôde ser configurado (requer --cap-add=NET_ADMIN)"
            echo "   O container funcionará sem isolamento de rede."
        }
    fi
else
    echo "ℹ️  Firewall desabilitado (ENABLE_FIREWALL=false)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Comandos disponíveis:"
echo "  ralph-loop.sh     - Iniciar loop Ralph autônomo"
echo "  claude            - Claude Code interativo"
echo "  claude --help     - Ajuda do Claude Code"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Executar comando passado ou shell interativo
exec "$@"
