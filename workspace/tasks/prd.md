# Product Requirements Document - Exemplo

## Visão Geral
Este é um exemplo de PRD para o Ralph Loop. Substitua pelo seu projeto real.

## Objetivo
Criar uma aplicação web simples de lista de tarefas (TODO list).

## Stack Tecnológica
- Frontend: HTML, CSS, JavaScript vanilla
- Backend: Não necessário (localStorage)
- Estrutura: Single Page Application

## Requisitos Funcionais

### RF1 - Estrutura Base
- [ ] Criar arquivo `index.html` com estrutura HTML5 semântica
- [ ] Criar arquivo `style.css` com estilos responsivos
- [ ] Criar arquivo `app.js` com lógica da aplicação

### RF2 - Interface do Usuário
- [ ] Campo de input para nova tarefa
- [ ] Botão de adicionar tarefa
- [ ] Lista de tarefas exibindo todas as tasks
- [ ] Cada tarefa deve ter checkbox para marcar como completa
- [ ] Botão de deletar para cada tarefa

### RF3 - Funcionalidades
- [ ] Adicionar nova tarefa ao pressionar Enter ou clicar no botão
- [ ] Marcar/desmarcar tarefa como completa
- [ ] Deletar tarefa individual
- [ ] Persistir tarefas no localStorage
- [ ] Carregar tarefas do localStorage ao iniciar

### RF4 - Estilização
- [ ] Layout centralizado e responsivo
- [ ] Tarefas completas devem ter texto riscado
- [ ] Feedback visual ao hover nos botões
- [ ] Cores agradáveis e contraste adequado

## Critérios de Aceitação
1. Aplicação funciona sem erros no console
2. Tarefas persistem após recarregar a página
3. Interface é utilizável em mobile e desktop
4. Código está organizado e comentado

## Notas para o Agente
- Faça commits frequentes com mensagens descritivas
- Teste cada funcionalidade antes de marcar como completa
- Se encontrar um bug, documente e corrija antes de prosseguir
