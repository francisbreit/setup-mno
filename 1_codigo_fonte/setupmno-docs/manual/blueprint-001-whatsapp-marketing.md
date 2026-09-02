# Manual Operacional: Blueprint #001 — WhatsApp Marketing Completo

---

## 1. Identificação e Maturidade
- **Blueprint ID:** `blueprint-001-whatsapp-marketing-completo`
- **Versão:** `1.0.0`
- **Maturidade:** `homologated` (Produção)
- **Ambientes Homologados:** WSL2 + Docker Desktop (x86_64) e VPS Ubuntu/Debian (x86_64 / ARM64)
- **Data da Homologação:** 31/08/2026
- **Responsável:** Francis Breit (Francis MNO)

---

## 2. Para Iniciantes (Visão Didática)

### O que este Blueprint faz?
Ele cria uma máquina profissional de marketing, automação e vendas pelo WhatsApp para você e sua empresa. Em vez de enviar mensagens manualmente pelo celular correndo o risco de ter o número bloqueado, este sistema:
1. **Organiza seus contatos:** O Mautic separa seus clientes por tags e segmentações;
2. **Protege seu chip (Anti-Ban):** O n8n e o RabbitMQ colocam as mensagens em uma fila organizada, enviando uma a uma com pausas inteligentes de 5 a 15 segundos para simular digitação humana;
3. **Conversa no piloto automático:** Se for uma mensagem interativa, o Typebot conversa com o cliente, envia áudios e qualifica o lead;
4. **Atendimento Humano:** Se o cliente pedir ajuda ou fizer uma pergunta complexa, a conversa cai instantaneamente na tela dos atendentes no Chatwoot.

### Vídeo Tutorial e Materiais de Apoio
- **Vídeo Passo a Passo:** Disponível na Área de Membros Francis MNO (`[EM BREVE]`);
- **PDF de Início Rápido:** `00_Guia_de_Inicio.pdf` incluso no pacote `.zip`;
- **Workflows e Templates:** Inclui 2 fluxos do n8n, modelos de mensagens e template do Typebot.

---

## 3. Nota Técnica para DevOps

### Topologia e Componentes
- **Mautic 7 WhatsApp Mkt:** Origem dos eventos e segmentações com plugin Twilio customizado (`x-api-token: 207811`);
- **n8n v2 (Modo Fila):** Worker e Webhook desacoplados;
- **RabbitMQ:** Fila Quorum (`Atendimento`) com persistência em disco e clustering nativo;
- **Evolution API v2:** Engine Baileys WhatsApp com webhooks bidirecionais;
- **Chatwoot:** Plataform App (`N8N`) e caixa de entrada integrada;
- **Typebot v3.18:** Next.js standalone multi-homed (`HOSTNAME=0.0.0.0`) conectado ao MinIO S3.

### Requisitos de Recursos Medidos em Homologação
- **RAM Ativa:** ~5.8 GiB (medido com 7 stacks ativas em Docker Desktop);
- **Mínimo Recomendado:** 8 GB de RAM;
- **Recomendado para Produção:** 12 GB a 16 GB de RAM.

---

## 4. Roteiro Oficial em 15 Passos

1. **Instalação do Combo de Comunicação:**
   - Execute o instalador `CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*` (ou o combo direto);
   - Configure subdomínios: `atend.`, `evo.`, `fila.` e `s3.`.
2. **Instalação do Mautic 7:**
   - Execute `MAUTIC 7 WHATSAPP MKT` com subdomínio `mkt.seu-dominio.com`.
3. **Instalação do n8n v2 em Modo Fila:**
   - Execute `N8N V2 - FILA (QUEUE)` com subdomínios `n8n.` e `webhook.`.
4. **Instalação do Typebot + MinIO:**
   - Execute `TYPEBOT + MINIO*` com subdomínios `adminchat.` (Builder) e `chat.` (Viewer).
5. **Primeiro Acesso ao Chatwoot:**
   - Crie a conta de administrador em `https://atend.seu-dominio.com`.
6. **Access Token do Chatwoot:**
   - Obtenha o token em Configurações de Perfil para uso no n8n.
7. **Platform App no Chatwoot:**
   - Crie o Platform App `N8N` no superadmin (`/super_admin`) e guarde o token.
8. **Configuração da Evolution API:**
   - Crie a instância Baileys `Atendimento`, ative a integração Chatwoot e escaneie o QR Code.
9. **Fila Quorum no RabbitMQ:**
   - No painel do RabbitMQ (`https://fila.seu-dominio.com`), crie a fila Quorum `Atendimento`.
10. **Ajustes no Mautic 7:**
    - Defina fuso horário e dados da empresa nas Configurações do Mautic.
11. **Configuração do n8n e Workflows:**
    - Crie a credencial RabbitMQ e importe os 2 fluxos JSON da pasta `01_N8N_Workflows`.
12. **Integração Evolution API + Typebot:**
    - Vincule a URL do Typebot Viewer nas configurações da instância no Evolution Manager.
13. **Plugin Twilio no Mautic e Teste Simples:**
    - Configure o webhook do n8n Receptor (Auth Token `207811`) e dispare um teste de texto simples.
14. **Importação do Chatbot no Typebot:**
    - Importe `typebot-aniversario-template.json` e publique o bot `aniversario`.
15. **Disparo de Campanha com Chatbot e Transbordo:**
    - Envie a campanha interativa e valide o fluxo do Typebot com transbordo para o Chatwoot.
