#!/bin/bash
# Ralph Loop - Loop autônomo para Claude Code
# Baseado na técnica de Geoffrey Huntley

set -e

# Configurações padrão
MAX_ITERATIONS=${MAX_ITERATIONS:-50}
COMPLETION_PROMISE=${COMPLETION_PROMISE:-"<promise>COMPLETE</promise>"}
RATE_LIMIT_CALLS=${RATE_LIMIT_CALLS:-100}
RATE_LIMIT_WINDOW=${RATE_LIMIT_WINDOW:-3600}  # 1 hora em segundos
TIMEOUT_MINUTES=${TIMEOUT_MINUTES:-30}
PRD_FILE=${PRD_FILE:-"tasks/prd.md"}
PROGRESS_FILE=${PROGRESS_FILE:-"tasks/progress.md"}

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Contadores
iteration=0
api_calls=0
window_start=$(date +%s)

# Função para log com timestamp
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Função para verificar rate limit
check_rate_limit() {
    local now=$(date +%s)
    local elapsed=$((now - window_start))
    
    if [ $elapsed -ge $RATE_LIMIT_WINDOW ]; then
        # Reset window
        window_start=$now
        api_calls=0
        log "${GREEN}Rate limit window resetado${NC}"
    fi
    
    if [ $api_calls -ge $RATE_LIMIT_CALLS ]; then
        local wait_time=$((RATE_LIMIT_WINDOW - elapsed))
        log "${YELLOW}⏳ Rate limit atingido. Aguardando ${wait_time}s...${NC}"
        sleep $wait_time
        window_start=$(date +%s)
        api_calls=0
    fi
}

# Função para criar arquivos de tarefa se não existirem
init_task_files() {
    mkdir -p "$(dirname "$PRD_FILE")"
    mkdir -p "$(dirname "$PROGRESS_FILE")"
    
    if [ ! -f "$PRD_FILE" ]; then
        log "${YELLOW}⚠️  PRD não encontrado em $PRD_FILE${NC}"
        log "Crie o arquivo PRD antes de iniciar o loop."
        log "Exemplo de estrutura:"
        echo ""
        echo "# Product Requirements Document"
        echo ""
        echo "## Objetivo"
        echo "Descreva o objetivo do projeto"
        echo ""
        echo "## Tarefas"
        echo "- [ ] Tarefa 1"
        echo "- [ ] Tarefa 2"
        echo "- [ ] Tarefa 3"
        echo ""
        exit 1
    fi
    
    if [ ! -f "$PROGRESS_FILE" ]; then
        echo "# Progress Tracking" > "$PROGRESS_FILE"
        echo "" >> "$PROGRESS_FILE"
        echo "## Completed" >> "$PROGRESS_FILE"
        echo "" >> "$PROGRESS_FILE"
        echo "## In Progress" >> "$PROGRESS_FILE"
        echo "" >> "$PROGRESS_FILE"
        log "${GREEN}✓ Arquivo de progresso criado: $PROGRESS_FILE${NC}"
    fi
}

# Função para construir o prompt
build_prompt() {
    cat << EOF
Você é um agente de desenvolvimento autônomo trabalhando em um loop Ralph.

INSTRUÇÕES CRÍTICAS:
1. Leia o PRD em '$PRD_FILE' para entender o escopo completo
2. Leia o progresso em '$PROGRESS_FILE' para saber o que já foi feito
3. Identifique a PRÓXIMA tarefa pendente (não marcada como completa)
4. Implemente APENAS essa tarefa
5. Após implementar, atualize o arquivo de progresso
6. Faça commit das mudanças com mensagem descritiva

REGRAS:
- Trabalhe em UMA tarefa por iteração
- Seja conservador - prefira mudanças pequenas e testáveis
- Se encontrar um erro, documente e tente resolver
- Se estiver bloqueado após 3 tentativas, documente o bloqueio

CONCLUSÃO:
- Quando TODAS as tarefas do PRD estiverem completas, output exatamente:
  $COMPLETION_PROMISE
- Não output esse texto até que TUDO esteja realmente completo

Iteração atual: $iteration de $MAX_ITERATIONS
EOF
}

# Função principal do loop
run_loop() {
    log "${GREEN}🚀 Iniciando Ralph Loop${NC}"
    log "   PRD: $PRD_FILE"
    log "   Progress: $PROGRESS_FILE"
    log "   Max iterações: $MAX_ITERATIONS"
    log "   Rate limit: $RATE_LIMIT_CALLS calls/$RATE_LIMIT_WINDOW s"
    echo ""
    
    init_task_files
    
    while [ $iteration -lt $MAX_ITERATIONS ]; do
        iteration=$((iteration + 1))
        log "${YELLOW}━━━ Iteração $iteration/$MAX_ITERATIONS ━━━${NC}"
        
        # Verificar rate limit
        check_rate_limit
        
        # Construir e executar prompt
        local prompt=$(build_prompt)
        
        # Executar Claude Code
        log "Executando Claude Code..."
        
        local output
        local exit_code=0
        
        # Timeout de segurança
        output=$(timeout "${TIMEOUT_MINUTES}m" claude \
            --dangerously-skip-permissions \
            --print \
            --output-format text \
            "$prompt" 2>&1) || exit_code=$?
        
        api_calls=$((api_calls + 1))
        
        # Verificar timeout
        if [ $exit_code -eq 124 ]; then
            log "${RED}⏰ Timeout atingido (${TIMEOUT_MINUTES}min)${NC}"
            continue
        fi
        
        # Verificar erro
        if [ $exit_code -ne 0 ]; then
            log "${RED}❌ Erro na execução (código: $exit_code)${NC}"
            
            # Verificar se é rate limit do Claude
            if echo "$output" | grep -qi "rate limit\|5-hour\|usage limit"; then
                log "${YELLOW}⏳ Rate limit da API detectado. Aguardando 5 minutos...${NC}"
                sleep 300
            fi
            continue
        fi
        
        # Verificar conclusão
        if echo "$output" | grep -qF "$COMPLETION_PROMISE"; then
            log "${GREEN}🎉 PROJETO COMPLETO!${NC}"
            log "Total de iterações: $iteration"
            echo ""
            echo "$output"
            exit 0
        fi
        
        # Log resumido do output
        log "Output recebido ($(echo "$output" | wc -c) bytes)"
        
        # Pequena pausa entre iterações
        sleep 2
    done
    
    log "${RED}⚠️  Max iterações atingido ($MAX_ITERATIONS)${NC}"
    log "O projeto pode não estar completo. Verifique o progresso manualmente."
    exit 1
}

# Help
show_help() {
    echo "Ralph Loop - Loop autônomo para Claude Code"
    echo ""
    echo "Uso: ralph-loop.sh [opções]"
    echo ""
    echo "Opções (via variáveis de ambiente):"
    echo "  MAX_ITERATIONS      Número máximo de iterações (padrão: 50)"
    echo "  COMPLETION_PROMISE  Texto que indica conclusão (padrão: <promise>COMPLETE</promise>)"
    echo "  RATE_LIMIT_CALLS    Chamadas máximas por janela (padrão: 100)"
    echo "  RATE_LIMIT_WINDOW   Janela de rate limit em segundos (padrão: 3600)"
    echo "  TIMEOUT_MINUTES     Timeout por iteração em minutos (padrão: 30)"
    echo "  PRD_FILE            Caminho do arquivo PRD (padrão: tasks/prd.md)"
    echo "  PROGRESS_FILE       Caminho do arquivo de progresso (padrão: tasks/progress.md)"
    echo ""
    echo "Exemplo:"
    echo "  MAX_ITERATIONS=100 PRD_FILE=docs/requirements.md ralph-loop.sh"
}

# Main
case "${1:-}" in
    -h|--help|help)
        show_help
        exit 0
        ;;
    *)
        run_loop
        ;;
esac
