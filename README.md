# 🚀 Setup MNO — Orquestrador Docker Swarm Open-Source para Automações e IA

<p align="center">
  <img src="1_codigo_fonte/setup-mno-logo.svg" alt="Setup MNO Logo" width="160px">
</p>

<p align="center">
  <strong>Infraestrutura de nuvem privada, leve, ultra-rápida e 100% segura para rodar mais de 157 aplicações de automação, IA e marketing sem gastar recursos com painéis pesados.</strong>
</p>

<p align="center">
  <a href="#-instalação-rápida-em-1-comando"><img src="https://img.shields.io/badge/Instalação-1--Clique-brightgreen.svg" alt="Instalação 1-Clique"></a>
  <a href="#-diferenciais-vs-concorrentes"><img src="https://img.shields.io/badge/RAM_Ociosa-0_MB-blue.svg" alt="0 MB RAM"></a>
  <a href="#-arquiteturas-suportadas"><img src="https://img.shields.io/badge/Arquitetura-x86__64_%7C_ARM64-orange.svg" alt="x86_64 e ARM64"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Licen%C3%A7a-MIT-green.svg" alt="Licença MIT"></a>
  <a href="https://academia.manualnegocioonline.com.br"><img src="https://img.shields.io/badge/Comunidade-Academia_MNO-purple.svg" alt="Academia MNO"></a>
</p>

---

## ⚡ O que é o Setup MNO?

O **Setup MNO** é uma suíte completa de orquestração de infraestrutura baseada em **Docker Swarm**, **Traefik v3**, **Cloudflare Tunnel** e scripts **Bash nativos**. 

Diferente de alternativas do mercado que consomem de 1.5 GB a 2.5 GB de memória RAM apenas para manter uma interface web ligada, o Setup MNO opera diretamente via terminal e menus visuais interativos (Whiptail/Dialog):
* **0 MB de memória RAM ociosa:** Toda a memória da sua VPS é 100% dedicada aos seus negócios, agentes de IA e clientes.
* **Zero Portas Abertas no Firewall:** Integração nativa com **Cloudflare Tunnel** e redes overlay isoladas (`interna`). Nenhuma porta administrativa (80, 443, 3000, 9000) precisa ficar exposta à internet pública.
* **157+ Ferramentas Homologadas em 1 Clique:** n8n, Evolution API v2, Chatwoot, Typebot, Mautic 7, Flowise, Dify, Qdrant, MinIO, RabbitMQ, PostgreSQL, Redis e muito mais.
* **Paridade Total x86-64 e ARM64:** Compatibilidade nativa com servidores convencionais e instâncias ARM gratuitas (ex: Oracle Cloud Ampere, AWS Graviton, Raspberry Pi).

---

## 💻 Instalação Rápida em 1 Comando

Em uma VPS limpa (Debian 11/12/13, Ubuntu 20.04/22.04/24.04 ou Windows 10/11 com WSL2 + Docker Desktop), execute como **root**:

```bash
curl -fsSL https://raw.githubusercontent.com/francisbreit/setup-mno/master/install.sh | bash
```

> **Tempo de inicialização:** Menos de 2 segundos. Sem compilações lentas, sem travas e sem riscos de expiração.

---

## 🏆 Matriz Comparativa: Setup MNO vs. Alternativas

| Critério | Setup MNO (Open-Source) | Coolify / Easypanel | Portainer Puro | Scripts de YouTube |
| :--- | :---: | :---: | :---: | :---: |
| **Consumo de RAM Ociosa** | **0 MB** (opera sob demanda) | 1.5 GB ~ 2.5 GB | 300 MB ~ 500 MB | Variável / Desconhecido |
| **Portas Abertas na VPS** | **Zero** (Cloudflare Tunnel nativo) | Múltiplas portas expostas | Portas 9000/9443 abertas | Portas 80/443 expostas |
| **Orquestração Nativa** | **Docker Swarm** (Alta Resiliência) | Docker Standalone | Requer config manual | Docker Compose simples |
| **Combos Prontos em 1 Clique** | **Sim** (Ex: Chatwoot + Evolution + RabbitMQ + S3) | Não (containers avulsos) | Não (stacks manuais) | Não |
| **Proteção Anti-Queda de Rede** | **Sim** (Sessão TMUX nativa) | Não se fechar navegador | Não | Não |
| **Compatibilidade ARM64** | **100% Homologado** | Parcial | Sim | Rara |
| **Laboratório Local no WSL2** | **Sim** (Paridade de Produção) | Complexo / Pesado | Básico | Quase impossível |

---

## 📦 Ecossistema de Aplicações Disponíveis

O Setup MNO já vem preparado com 157 setups prontos divididos nas seguintes categorias:

* **🤖 Inteligência Artificial & LLMs:** Dify, Flowise, AnythingLLM, Qdrant Vector DB, Ollama, LibreTranslate.
* **💬 Atendimento & WhatsApp:** Chatwoot Desbloqueado, Evolution API v2, Typebot, Waha, QuePasa.
* **⚙️ Automação & Workflows:** n8n (com suporte a fila Redis/RabbitMQ), Activepieces, Kestra.
* **📧 Email & WhatsApp Marketing:** Mautic 7 Padrão e WhatsMkt, Listmonk, Mailpit.
* **🗄️ Bancos de Dados & Storage:** PostgreSQL 16 com PgBouncer, MySQL 8, Redis, MinIO S3, ClickHouse, Metabase.
* **🛡️ Infraestrutura & Monitoramento:** Traefik v3, Portainer CE, Uptime Kuma, AdGuard Home, Netdata.

---

## 🏢 Casos de Negócios e Monetização

O Setup MNO foi desenhado não apenas para entusiastas de tecnologia, mas para **makers digitais e agências que prestam serviços B2B de alto valor**:

1. **Agência de Agentes de IA para Clínicas e Negócios Locais:** Instale atendimento automatizado 24/7 no WhatsApp de clínicas médicas e odontológicas cobrando **R$ 3.500 de implementação** e **R$ 597/mês de sustentação recorrente**.
2. **Hospedagem Gerenciada Privada:** Migre clientes pagando planos caros em SaaS (RD Station, Zendesk, Make) para instâncias privadas sem limites de usuários e contatos.
3. **Proteção Anti-Bloqueio de WhatsApp:** Arquitetura com filas assíncronas no RabbitMQ (Quorum queues) e atrasos humanizados para manter os números dos clientes protegidos.

---

## 🎓 Academia MNO & Comunidade VIP

Quer aprender a construir agentes de IA autônomos, baixar Blueprints prontos de n8n e fazer parte da maior comunidade de automação open-source do Brasil?

* 🌐 **Comunidade Oficial:** [academia.manualnegocioonline.com.br](https://academia.manualnegocioonline.com.br)
* 📺 **Canal do YouTube:** [@FrancisMNO](https://www.youtube.com/@FrancisMNO)
* 💼 **Contato Profissional:** [contato@manualnegocioonline.com.br](mailto:contato@manualnegocioonline.com.br)

---

## 📄 Licença

Este projeto é distribuído sob a licença **MIT**. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

---

<p align="center">
  Criado com paixão por <strong>Francis Breit (Francis MNO)</strong> para a comunidade maker e open-source brasileira.
</p>
