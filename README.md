# Ralph Wiggum Loop with Docker Setup

## Sobre a Técnica Ralph Wiggum

A **Ralph Wiggum Technique** é uma metodologia de coding autônomo criada por Geoffrey Huntley que viralizou no final de 2025. Na sua forma mais pura, é um loop Bash:

```bash
while :; do cat PROMPT.md | claude ; done
```

A ideia central é **deterministically bad in an undeterministic world** — ao invés de acumular contexto em conversas longas (onde o modelo perde qualidade), cada iteração começa com **contexto limpo** de 200K tokens. O estado persiste apenas via arquivos no disco.

### Como funciona

O loop opera em **três fases, dois prompts e um loop**:

1. **Planning Phase** — Claude analisa as specs e o código existente, gera um `IMPLEMENTATION_PLAN.md` com tarefas priorizadas. Nenhum código é escrito.
2. **Building Phase** — A cada iteração, Claude pega a tarefa mais importante do plano, implementa, roda validação (testes, lint, typecheck), faz commit e sai. O loop reinicia com contexto fresco.
3. **Observation Phase** — Você. Seu papel é **sentar no loop, não dentro dele**. Observe padrões de falha, ajuste prompts, atualize o `AGENTS.md` com aprendizados.

### Backpressure

O conceito-chave é **backpressure**: testes, linting e type checking funcionam como válvulas que rejeitam trabalho inválido. Se o código não passa na validação, Ralph investiga e corrige — criando um ciclo auto-corretivo sem intervenção manual.

### Docker como isolamento

Ralph roda com `--dangerously-skip-permissions`, ou seja, executa comandos sem confirmação. O modo Docker isola a execução em um container, limitando acesso ao filesystem e prevenindo modificações acidentais no sistema.

---

## Estrutura do Projeto

```
jogo-da-velha/
├── loop.sh                 # Script principal do loop (execução direta)
├── loop-docker.sh          # Loop via Docker (isolado)
├── Dockerfile              # Definição do container
├── PROMPT_plan.md          # Instruções do modo planejamento
├── PROMPT_build.md         # Instruções do modo construção
├── AGENTS.md               # Aprendizados operacionais (evolui com o tempo)
├── IMPLEMENTATION_PLAN.md  # Plano de tarefas (gerado pelo planning mode)
├── specs/                  # Especificações do projeto
│   └── jogo-da-velha.md    # Spec completa do jogo
└── src/                    # Código-fonte (gerado pelo Ralph)
```

---

## Pré-requisitos

- [Docker](https://www.docker.com/) instalado (para modo isolado)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) instalado (`npm install -g @anthropic-ai/claude-code`)
- Token OAuth configurado:

```bash
claude setup-token
echo "SEU_TOKEN" > ~/.claude-oauth-token
chmod 600 ~/.claude-oauth-token
```

---

## How to Run

### Modo Docker (Recomendado)

```bash
# 1. Build da imagem Docker
./loop-docker.sh --build-image

# 2. Planejamento — gera o IMPLEMENTATION_PLAN.md
./loop-docker.sh plan

# 3. Construção — implementa tarefa por tarefa
./loop-docker.sh

# Com limite de iterações:
./loop-docker.sh 20
```

### Modo Direto (sem Docker)

```bash
# 1. Planejamento
./loop.sh plan

# 2. Construção
./loop.sh

# Com limite:
./loop.sh 20

# Usando Sonnet (mais rápido e barato):
./loop.sh --model sonnet
```

### Monitoramento

```bash
# Acompanhar em tempo real
tail -f ralph.log

# Ver progresso das tarefas
grep -c '\[x\]' IMPLEMENTATION_PLAN.md  # completas
grep -c '\[ \]' IMPLEMENTATION_PLAN.md  # pendentes

# Ver commits do Ralph
git log --oneline
```

### Controles

| Comando | Ação |
|---------|------|
| `Ctrl+C` | Para o loop |
| `rm IMPLEMENTATION_PLAN.md && ./loop-docker.sh plan` | Regenera o plano |
| `RALPH_MODEL=sonnet ./loop-docker.sh` | Usa modelo Sonnet |
| `RALPH_BACKUP=false ./loop-docker.sh` | Desativa backup remoto |
| `RALPH_MAX_STUCK=5 ./loop-docker.sh` | Aumenta tolerância a falhas |

---

## Variáveis de Ambiente

| Variável | Default | Descrição |
|----------|---------|-----------|
| `RALPH_MODEL` | `opus` | Modelo Claude (opus, sonnet, haiku) |
| `RALPH_MAX_STUCK` | `3` | Tentativas antes de pular tarefa |
| `RALPH_BACKUP` | `true` | Push automático para GitHub |
| `RALPH_VERBOSE` | `false` | Logging detalhado |
| `CLAUDE_CODE_OAUTH_TOKEN` | — | Token OAuth (ou usar ~/.claude-oauth-token) |
