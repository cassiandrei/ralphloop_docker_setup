# Ralph Loop Docker Environment
# Baseado no devcontainer oficial com firewall de segurança
FROM ubuntu:24.04

# Evitar prompts interativos
ENV DEBIAN_FRONTEND=noninteractive

# Instalar dependências base
RUN apt-get update && apt-get install -y \
    curl \
    git \
    iptables \
    ipset \
    dnsutils \
    ca-certificates \
    sudo \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Instalar Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Instalar Claude Code CLI globalmente
RUN npm install -g @anthropic-ai/claude-code

# Criar usuário não-root para segurança
RUN useradd -m -s /bin/bash claude \
    && echo "claude ALL=(ALL) NOPASSWD: /usr/sbin/iptables, /usr/sbin/ip6tables, /usr/sbin/ipset" >> /etc/sudoers

# Copiar scripts
COPY scripts/init-firewall.sh /usr/local/bin/init-firewall.sh
COPY scripts/ralph-loop.sh /usr/local/bin/ralph-loop.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/*.sh

# Configurar diretório de trabalho
WORKDIR /workspace

# Mudar para usuário claude
USER claude

# Criar diretório .claude para credenciais
RUN mkdir -p /home/claude/.claude

# Entrypoint configura firewall e inicia shell
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
