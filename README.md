# Ralph Loop Docker Environment

Ambiente Docker seguro para rodar Claude Code em loop autônomo (Ralph Loop) usando sua assinatura Max — **sem API key**.

## 🔒 Segurança

Este setup inclui:
- **Firewall com whitelist**: Apenas domínios essenciais são permitidos (Claude API, npm, GitHub)
- **Isolamento de container**: O código roda isolado do seu sistema
- **Usuário não-root**: Claude Code roda com usuário limitado
- **Rate limiting**: Proteção contra loops infinitos e uso excessivo

## 📋 Pré-requisitos

1. **Docker Desktop** instalado e rodando
2. **Assinatura Claude Max** ativa
3. **Claude Code CLI** instalado no host (para gerar o token)

```bash
# Instalar Claude Code no host (uma vez só)
npm install -g @anthropic-ai/claude-code
```

## 🚀 Quick Start

### 1. Gerar token OAuth (no host)

```bash
claude setup-token
```

Copie o token gerado (começa com `sk-ant-oat01-...`).

### 2. Configurar ambiente

```bash
# Copiar exemplo de configuração
cp .env.example .env

# Editar e adicionar seu token
nano .env  # ou seu editor preferido
```

### 3. Criar seu PRD

Edite `workspace/tasks/prd.md` com os requisitos do seu projeto.

### 4. Rodar o loop

```bash
# Build da imagem (primeira vez)
docker compose build

# Rodar loop autônomo
docker compose run loop

# OU entrar no container interativamente
docker compose run ralph
```

## 📁 Estrutura

```
ralph-docker-setup/
├── Dockerfile              # Imagem com Claude Code e firewall
├── docker-compose.yml      # Orquestração
├── .env.example            # Exemplo de configuração
├── scripts/
│   ├── entrypoint.sh       # Inicialização do container
│   ├── init-firewall.sh    # Configuração de firewall
│   └── ralph-loop.sh       # Script do loop Ralph
└── workspace/              # Seu projeto (montado no container)
    └── tasks/
        ├── prd.md          # Product Requirements Document
        └── progress.md     # Progresso (gerado automaticamente)
```

## ⚙️ Configurações

Variáveis de ambiente (defina no `.env`):

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `CLAUDE_CODE_OAUTH_TOKEN` | - | Token OAuth da assinatura Max (obrigatório) |
| `MAX_ITERATIONS` | 50 | Máximo de iterações do loop |
| `TIMEOUT_MINUTES` | 30 | Timeout por iteração |
| `RATE_LIMIT_CALLS` | 100 | Máximo de chamadas por hora |
| `PRD_FILE` | tasks/prd.md | Caminho do arquivo PRD |
| `PROGRESS_FILE` | tasks/progress.md | Caminho do arquivo de progresso |
| `ENABLE_FIREWALL` | true | Habilitar firewall de segurança |

## 🔥 Firewall

O firewall bloqueia todas as conexões de saída exceto:

**Permitidos:**
- `api.anthropic.com` - API do Claude
- `claude.ai` - Autenticação
- `registry.npmjs.org` - npm packages
- `pypi.org` - Python packages
- `github.com`, `gitlab.com` - Git
- DNS (1.1.1.1, 8.8.8.8)

**Bloqueados:**
- Todo o resto (rede local, outros sites, etc.)

Para desabilitar (não recomendado):
```bash
ENABLE_FIREWALL=false docker compose run ralph
```

## 📝 Escrevendo um bom PRD

O Ralph funciona melhor com PRDs bem estruturados:

```markdown
# Nome do Projeto

## Objetivo
Descrição clara do que deve ser construído.

## Tarefas
- [ ] Tarefa pequena e específica 1
- [ ] Tarefa pequena e específica 2
- [ ] Tarefa pequena e específica 3

## Critérios de Aceitação
- O que define "pronto"
```

**Dicas:**
- Tarefas devem ser pequenas (completáveis em uma iteração)
- Seja específico sobre tecnologias e estrutura
- Inclua critérios de aceitação claros

## 🐛 Troubleshooting

### "Token inválido" ou erro de autenticação
```bash
# Regenerar token no host
claude setup-token

# Atualizar .env com novo token
```

### Firewall não funciona
```bash
# Verificar se Docker tem permissão
docker compose run --cap-add=NET_ADMIN ralph
```

### Loop para antes de completar
- Aumente `MAX_ITERATIONS`
- Verifique se as tarefas não são muito grandes
- Confira o arquivo de progresso para ver onde parou

### Rate limit da Anthropic
O script detecta automaticamente e aguarda. Se persistir:
- Reduza `RATE_LIMIT_CALLS`
- Aguarde o reset do limite (geralmente 5 horas)

## 🤝 Uso Interativo

Além do loop autônomo, você pode usar o Claude Code interativamente:

```bash
# Entrar no container
docker compose run ralph

# Dentro do container:
claude  # modo interativo
claude "sua pergunta aqui"  # modo direto
```

## ⚠️ Avisos Importantes

1. **Revise o código gerado**: O loop é autônomo mas você deve revisar as mudanças
2. **Use em projetos de teste primeiro**: Familiarize-se antes de usar em produção
3. **Mantenha backups**: O agente pode fazer mudanças destrutivas
4. **Monitore o uso**: Sua assinatura Max tem limites

## 📚 Referências

- [Claude Code Docs](https://docs.claude.com)
- [Ralph Loop Original (Geoffrey Huntley)](https://www.aihero.dev/getting-started-with-ralph)
- [DevContainer Oficial](https://code.claude.com/docs/en/devcontainer)
