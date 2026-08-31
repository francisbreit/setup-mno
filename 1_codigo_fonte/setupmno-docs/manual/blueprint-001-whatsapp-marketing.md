# Manual Operacional: Blueprint #001 — WhatsApp Marketing Completo

---

## 1. Identificação e Maturidade
- **Blueprint ID:** `blueprint-001-whatsapp-marketing-completo`
- **Maturidade:** `homologated`
- **Ambientes Homologados:** WSL2 + Docker Desktop (x86_64) e VPS Ubuntu/Debian (x86_64 / ARM64)
- **Data da Homologação:** 31/08/2026
- **Responsável:** Francis Breit (Francis MNO)

---

## 2. Para Iniciantes (Visão Didática)

### O que este Blueprint faz?
Ele cria uma máquina profissional de marketing, automação e vendas pelo WhatsApp para você e sua empresa. Em vez de enviar mensagens manualmente pelo celular correndo o risco de ter o número bloqueado, este sistema:
1. **Organiza seus contatos:** O Mautic separa seus clientes por tags (ex: clientes VIP, aniversariantes, novos leads);
2. **Protege seu chip (Anti-Ban):** O n8n e o RabbitMQ colocam as mensagens em uma fila organizada, enviando uma a uma com pausas inteligentes de 5 a 15 segundos para simular digitação humana;
3. **Conversa no piloto automático:** Se for uma mensagem interativa, o Typebot conversa com o cliente, envia áudios e tira dúvidas;
4. **Atendimento Humano:** Se o cliente pedir ajuda ou fizer uma pergunta complexa, a conversa cai instantaneamente na tela dos atendentes no Chatwoot.

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

## 4. Roteiro Passo a Passo de Instalação e Configuração

1. **Instalar o Combo via Setup MNO:**
   - Execute o instalador `COMBO WHATSAPP MARKETING COMPLETO*` (ou instale os 4 combos individuais em ordem).
2. **Chatwoot:**
   - Crie o usuário inicial em `https://atend.seu-dominio.com`;
   - Obtenha o Access Token em Configurações de Perfil;
   - Crie o Platform App `N8N` no `/super_admin` e copie o token.
3. **Evolution API v2:**
   - Acesse o Manager `https://evo.seu-dominio.com/manager`;
   - Crie a instância Baileys `Atendimento`;
   - Na aba Integrações > Chatwoot, ative e aponte para a URL do Chatwoot;
   - Escaneie o QR Code no WhatsApp.
4. **RabbitMQ:**
   - Acesse `https://fila.seu-dominio.com`;
   - Na aba Queues, crie uma fila do tipo `Quorum` com o nome `Atendimento`.
5. **n8n v2:**
   - Importe os 2 workflows da pasta `01_N8N_Workflows`:
     - `Mautic-SMS-WhatsApp-receptor-Principal.json` (Webhook de recepção e publicação na fila);
     - `Mautic-SMS-WhatsApp-emissor-verificador-instanciaTeste.json` (Consumidor, rate limiting e disparo).
6. **Mautic 7:**
   - Acesse Configurações > Plugins > Twilio;
   - Insira o Webhook do n8n receptor e o Auth Token `207811`;
   - Dispare mensagens de broadcast com os modelos da pasta `02_Mautic_Campanhas`.
7. **Typebot:**
   - Importe o fluxo `03_Typebot_Templates/typebot-aniversario-template.json` e publique o bot `aniversario`.
