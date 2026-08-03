---
{
  "schemaVersion": 1,
  "documentId": "setup-flowise-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "aaee4eb5b5f00b88498664317535090dd205629599f605843717c701ccfa6da8",
  "documentType": "setup",
  "title": "Flowise no Setup MNO",
  "setupId": "flowise",
  "setupVersion": "7.7.6",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["flowise", "llm", "chatflow", "agentes", "low-code", "postgresql"],
  "sources": [
    {"sourceId":"flowise-installer","title":"Instalador Flowise","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/flowise.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"flowise-deployment","title":"Deployment oficial do Flowise","sourceType":"official-documentation","location":"https://docs.flowiseai.com/configuration/deployment","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"flowise-environment","title":"Variáveis oficiais do Flowise","sourceType":"official-documentation","location":"https://docs.flowiseai.com/configuration/environment-variables","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"flowise-rate-limit","title":"Rate limit oficial do Flowise","sourceType":"official-documentation","location":"https://docs.flowiseai.com/configuration/rate-limit","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Flowise no Setup MNO

## Quando usar

Use para desenhar chatflows e agentes de IA visualmente e expor fluxos por API.
É indicado para protótipos controlados e automações com responsáveis definidos;
não transforme um fluxo experimental em serviço público sem autenticação,
limites e testes de abuso.

## Arquitetura no Setup MNO

O instalador cria uma réplica Flowise conectada a um banco lógico no PostgreSQL
base. A rota passa pelo Traefik ou túnel e a imagem está fixada na série 2.0.6.
Usuário, senha e chave de criptografia são coletados ou gerados no fluxo. Não há
Redis, fila dedicada nem volume local declarado para arquivos.

## Pré-requisitos

Exige PostgreSQL saudável, domínio, RAM livre e credenciais separadas para cada
provedor ou ferramenta chamada. Mapeie antecipadamente quem pode editar fluxos,
quem consome APIs e quais dados externos podem ser processados.

## Fluxo seguro

O Instalador Seguro coleta domínio, acesso administrativo e modo Portainer ou
Docker, cria o banco e publica uma réplica. Depois, restrinja chatflows públicos,
configure autorização por API, rate limit e o número correto de proxies. Não
desative a checagem de segurança de MCP em produção.

## Primeiro acesso e integrações

Crie um fluxo mínimo com entrada fictícia e um provedor de teste. Valide a chave
de criptografia antes de adicionar credenciais. n8n, LiteLLM, Qdrant, SearXNG e
webhooks podem integrar-se ao Flowise, sempre com credenciais próprias, timeout,
limite de chamadas e proteção contra ciclos.

## Backup e atualização

Preserve o banco PostgreSQL e qualquer storage externo usado por documentos ou
uploads. Registre a imagem atual, exporte fluxos críticos e leia notas e
migrações antes de atualizar. A chave de criptografia deve permanecer estável;
perdê-la pode inutilizar credenciais armazenadas.

## Validação

Confirme login, persistência após recriar a réplica, execução de um chatflow,
autorização da API, rate limit, integração com o provedor e ausência de segredo
nos logs. Teste também falha do provedor e timeout.

## Riscos e limites

O instalador usa uma versão antiga e autenticação básica legada quando comparado
à documentação atual. A ausência de fila e de configuração de produção limita
escala e resiliência. Recomende somente após verificar compatibilidade da versão
e os controles necessários ao caso de uso.

## Diagnóstico

Separe rota, autenticação, PostgreSQL, descriptografia de credenciais, provedor,
ferramenta e limite de requisição. Use IDs sanitizados; nunca cole prompts,
chaves, credenciais salvas ou payloads reais no chat.
