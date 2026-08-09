---
{
  "schemaVersion": 1,
  "documentId": "setup-litellm-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "71b2013a7d6dc9c06049e3d2d5f06f4d98b402d76f0cb21d7b448db77142e9ce",
  "documentType": "setup",
  "title": "LiteLLM no Setup MNO",
  "setupId": "litellm",
  "setupVersion": "7.7.47",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["litellm", "llm", "gateway", "proxy", "postgresql", "chaves-virtuais"],
  "sources": [
    {"sourceId":"litellm-installer","title":"Instalador LiteLLM","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/litellm.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"litellm-production","title":"Deployment de produção oficial do LiteLLM","sourceType":"official-documentation","location":"https://docs.litellm.ai/docs/proxy/deploy","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"litellm-virtual-keys","title":"Chaves virtuais oficiais do LiteLLM","sourceType":"official-documentation","location":"https://docs.litellm.ai/docs/proxy/virtual_keys","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# LiteLLM no Setup MNO

## Quando usar

Use como gateway compatível com APIs de LLM para centralizar provedores,
modelos, chaves virtuais, limites e observabilidade. Ele passa a concentrar
credenciais e tráfego sensível; não é apenas uma interface web.

## Arquitetura no Setup MNO

O instalador cria uma réplica monolítica ligada a um banco lógico no PostgreSQL
base e publica a porta interna 4000. Gera uma master key durante a instalação e
usa imagem de desenvolvimento fixada em uma versão antiga. Não configura Redis,
migração separada nem `LITELLM_SALT_KEY` persistente.

## Pré-requisitos

Exige PostgreSQL saudável, domínio, política de acesso a modelos, orçamento,
rate limits e um cofre para master key, salt e chaves de provedores. A salt key
deve ser criada uma vez e preservada porque protege credenciais no banco.

## Fluxo seguro

O Instalador Seguro coleta domínio e acesso à UI, cria banco e publica o proxy.
Na implementação atual, a ausência de salt estável e o uso de imagem dev não
atendem ao desenho oficial de produção. A recomendação fica bloqueada até que
secrets, imagem, migração e healthchecks sejam corrigidos e homologados.

## Primeiro acesso e integrações

Depois da correção, cadastre um provedor de teste, gere chave virtual restrita a
um modelo e orçamento e faça chamada sem dados sensíveis. Dify, Flowise,
Langflow, Open WebUI e n8n podem consumir o endpoint com chaves diferentes.

## Backup e atualização

Preserve PostgreSQL, master key e principalmente a salt key. A documentação
oficial informa que trocar a salt após armazenar provedores torna suas
credenciais ilegíveis. Fixe versão estável, execute migração controlada e valide
rollback com backup anterior.

## Validação

Valide readiness, login, criação e revogação de chave virtual, restrição de
modelo, orçamento, chamada ao provedor, erro de credencial e ausência de chave
nos logs. Tela da UI não comprova o caminho completo.

## Riscos e limites

Risco crítico porque o gateway concentra todas as credenciais de IA. A release
atual do instalador não preserva a chave de criptografia exigida no desenho
moderno e usa build de desenvolvimento antigo. Não recomende para produção.

## Diagnóstico

Separe rota, readiness, PostgreSQL, master key, salt, chave virtual, modelo e
provedor. Use apenas códigos e métricas agregadas; nunca envie master key, salt,
chave de provedor, prompt real ou resposta de cliente.
