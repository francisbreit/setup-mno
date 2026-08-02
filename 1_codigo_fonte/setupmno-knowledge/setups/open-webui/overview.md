---
{
  "schemaVersion": 1,
  "documentId": "setup-open-webui-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "f992e320422dd5af3dd4c0ce8af809fdcda5299949fd29124d49dfcc992ee2c2",
  "documentType": "setup",
  "title": "Open WebUI sem Ollama no Setup MNO",
  "setupId": "open-webui",
  "setupVersion": "7.2.11",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["open-webui", "llm", "chat", "postgresql", "rag"],
  "sources": [
    {"sourceId":"open-webui-installer","title":"Instalador Open WebUI","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/openwebui.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"open-webui-quickstart","title":"Quick start oficial do Open WebUI","sourceType":"official-documentation","location":"https://docs.openwebui.com/getting-started/quick-start/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"open-webui-update","title":"Atualização e recuperação do Open WebUI","sourceType":"official-documentation","location":"https://docs.openwebui.com/getting-started/updating/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Open WebUI sem Ollama no Setup MNO

## Quando usar

Use como interface central de chat e conhecimento quando o provedor de modelo já
existe ou será configurado depois. Este setup não instala Ollama nem baixa
modelos. Para IA local completa, avalie o combo Ollama + Open WebUI e a RAM
necessária ao modelo.

## Arquitetura no Setup MNO

O instalador cria uma réplica Open WebUI, volume persistente, banco lógico no
PostgreSQL base e uma rota pública. Gera segredos próprios, permite decidir se
novos cadastros ficam abertos e bloqueia downloads automáticos de modelos no
boot. Nenhum provedor é conectado automaticamente.

## Pré-requisitos

Exige domínio, PostgreSQL saudável, volume, capacidade de memória e um plano de
identidade. Defina antes quem administra usuários, quais provedores de modelo
serão aceitos, onde os dados podem sair e se uploads ou bases RAG conterão dados
sensíveis.

## Fluxo seguro

O Instalador Seguro coleta domínio, política de cadastro e modo Portainer ou
Docker, cria banco, segredos e volume. Mantenha cadastro fechado em ambientes
privados e configure o primeiro administrador imediatamente. Conectores de LLM
devem usar chaves fora de logs e de conversas.

## Primeiro acesso e integrações

Valide login e permissões antes de conectar um provedor. Depois, configure um
modelo de teste, limite o acesso por usuário e revise retenção de chats, uploads,
ferramentas e funções. Um provedor OpenAI-compatible ou Ollama externo precisa
estar alcançável pela rede apropriada.

## Backup e atualização

Backup deve cobrir banco PostgreSQL, volume de dados e segredos persistentes.
Tags móveis facilitam atualização, mas podem trazer breaking changes; em uso de
equipe ou produção, fixe uma versão, leia as notas e teste migrações. Reverter a
imagem não desfaz migração de banco: restauração pode ser necessária.

## Validação

Confirme login, política de cadastro, persistência, conexão ao provedor, conversa
descartável e bloqueio de usuário não autorizado. Se usar conhecimento, teste
upload e recuperação apenas com documento sintético. Observe memória, erros de
modelo e latência.

## Riscos e limites

A imagem móvel usada pelo instalador reduz previsibilidade de atualização. Uma
interface funcional sem provedor não gera respostas. Ferramentas, uploads e RAG
podem enviar dados ao modelo escolhido; a governança depende do conector e da
configuração, não apenas do Open WebUI.

## Diagnóstico

Separe rota, autenticação, banco, volume, provedor e modelo. Informe modo de
falha e código sanitizado. Não envie chave de API, prompt real, documento de
cliente, conteúdo de chat ou segredos gerados pelo instalador.
