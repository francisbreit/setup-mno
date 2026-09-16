---
{
  "schemaVersion": 1,
  "documentId": "setup-combo-ia-whatsapp-sdr-crm-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ebcf011c5d96b68f41ed9aaf3a0291690bd2947372c3fb4f20e9beb556910331",
  "documentType": "setup",
  "title": "Combo Agente IA WhatsApp + CRM (SDR 24/7) no Setup MNO",
  "setupId": "combo-ia-whatsapp-sdr-crm",
  "setupVersion": "7.48.5",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-09-03",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "whatsapp",
    "ia",
    "sdr",
    "crm",
    "krayincrm",
    "chatwoot",
    "evolution-api",
    "rabbitmq",
    "minio",
    "n8n",
    "combo",
    "blueprint"
  ],
  "sources": [
    {
      "sourceId": "combo-ia-whatsapp-sdr-crm-installer",
      "title": "Instalador Combo Agente IA WhatsApp + CRM (SDR 24/7)",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/combo_ia_whatsapp_sdr_crm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-09-03"
    },
    {
      "sourceId": "krayin-crm-official-doc",
      "title": "Documentação oficial do Krayin CRM",
      "sourceType": "official-documentation",
      "location": "https://krayincrm.com/docs/",
      "license": "documentation-reference",
      "verifiedAt": "2026-09-03"
    },
    {
      "sourceId": "chatwoot-official-doc",
      "title": "Documentação oficial do Chatwoot",
      "sourceType": "official-documentation",
      "location": "https://developers.chatwoot.com/",
      "license": "documentation-reference",
      "verifiedAt": "2026-09-03"
    },
    {
      "sourceId": "n8n-official-documentation",
      "title": "Documentação oficial do n8n",
      "sourceType": "official-documentation",
      "location": "https://docs.n8n.io/",
      "license": "documentation-reference",
      "verifiedAt": "2026-09-03"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Combo Agente IA WhatsApp + CRM (SDR 24/7) no Setup MNO

## Quando usar

Use para provisionar e orquestrar em lote todo o ecossistema do Blueprint #002 (Agentes IA no WhatsApp com SDR 24/7, CRM e Follow-up Anti-Vácuo), integrando Chatwoot Desbloqueado v4, Evolution API v2, RabbitMQ com filas Quorum, MinIO para armazenamento de mídias/áudios, Krayin CRM e n8n v2 em modo fila. A recomendação é ideal para empresas que precisam de atendimento contínuo, qualificação automática de leads de vendas e sincronização de pipeline comercial sem intervenção humana preliminar.

## Arquitetura no Setup MNO

O combo orquestra múltiplos serviços interconectados na rede overlay segura `interna` do Docker Swarm. A mensageria é intermediada pelo RabbitMQ garantindo alta resiliência e failover; os áudios e anexos recebidos são depositados no MinIO S3; o n8n processa as mensagens via LangChain Agents e Whisper; e o Krayin CRM persiste contatos e negócios no funil de vendas. Toda a exposição web é protegida por Traefik com SSL automático ou Cloudflare Tunnel nativo com zero portas abertas no firewall.

## Pré-requisitos

Exige servidor VPS ou laboratório WSL2 com no mínimo 8 GB de RAM (recomendado 12 GB se integrado ao Mautic 7), processador de 4 vCPUs ou superior, rede overlay `interna` provisionada pelo Setup MNO, PostgreSQL central ativo e domínios/subdomínios configurados para cada aplicação.

## Fluxo seguro

Execute através do instalador interativo Whiptail do Setup MNO selecionando a opção do combo. O assistente inteligente inspeciona previamente o Docker Swarm; caso identifique stacks já em execução (como Chatwoot ou n8n de instalações anteriores), oferece a opção de reaproveitar a infraestrutura existente sem sobrescrever dados nem reinstalar dependências, provisionando exclusivamente os serviços pendentes (como Krayin CRM).

## Primeiro acesso e integrações

Após o provisionamento das aplicações, conecte a instância do WhatsApp na Evolution API via QR Code, crie a caixa de entrada no Chatwoot no canal de API, acerte as etapas do funil de vendas no Krayin CRM e importe os 4 workflows canônicos do n8n disponibilizados no pacote do Blueprint #002. Configure a chave de API da OpenAI, Groq ou endpoint local do Ollama para ativação do agente SDR e transcrição de voz.

## Backup e atualização

Realize o backup consolidado dos bancos de dados PostgreSQL e MySQL (Krayin CRM) e dos volumes persistentes de dados e buckets do MinIO antes de aplicar atualizações de imagem. As atualizações devem ser validadas individualmente por serviço no Swarm para manter a integridade das conexões e webhooks.

## Validação

Valide o ecossistema enviando uma mensagem de texto e uma mensagem de áudio via WhatsApp para a instância conectada; confirme o acionamento do webhook no n8n, a transcrição pelo Whisper, a resposta humanizada da IA com delay de digitação, a criação automática da pessoa e oportunidade no Krayin CRM e a injeção da nota privada de transbordo no Chatwoot quando solicitado atendimento humano.

## Riscos e limites

O uso de agentes de IA conversacionais exige supervisão de guardrails anti-alucinação e limites de caracteres por mensagem para prevenir banimentos de chips de WhatsApp. O consumo de memória pode atingir 8 GB a 10 GB durante execuções simultâneas de modelos e processamento assíncrono de filas.

## Diagnóstico

Em caso de falhas ou indisponibilidade, verifique a saúde dos serviços via `docker service ls`, inspecione logs específicos de stacks com `docker service logs <servico>`, valide a conectividade de rede overlay com `docker network inspect interna` e consulte o painel administrativo do RabbitMQ para checar a drenagem das filas.
