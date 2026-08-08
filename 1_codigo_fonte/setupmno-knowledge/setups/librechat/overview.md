---
{
  "schemaVersion": 1,
  "documentId": "setup-librechat-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "7663f176d7e600656f33983d6b2a405b4e65c5b652e994c5b118b1a2b069c7ca",
  "documentType": "setup",
  "title": "LibreChat no Setup MNO",
  "setupId": "librechat",
  "setupVersion": "7.7.32",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["librechat", "chat-ia", "llm", "mongodb", "multi-modelo"],
  "sources": [
    {"sourceId":"librechat-installer","title":"Instalador LibreChat","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/librechat.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"librechat-quickstart","title":"Quick start oficial do LibreChat","sourceType":"official-documentation","location":"https://www.librechat.ai/docs/quick_start","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"librechat-env","title":"Variáveis oficiais do LibreChat","sourceType":"official-documentation","location":"https://www.librechat.ai/docs/configuration/dotenv","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"librechat-docker","title":"Overrides Docker do LibreChat","sourceType":"official-documentation","location":"https://www.librechat.ai/docs/configuration/docker_override","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# LibreChat no Setup MNO

## Quando usar

Use quando usuários precisam uma interface central para vários provedores e
modelos de IA. Não confunda a interface com um provedor: custos, privacidade,
limites e disponibilidade continuam pertencendo a cada endpoint conectado.

## Arquitetura no Setup MNO

O script cria ou reutiliza um MongoDB compartilhado com credencial root e lança
somente a aplicação LibreChat em tag `latest`. Publica 3080 no host, deixa
cadastro aberto e não inclui Meilisearch, RAG API nem painel administrativo da
composição oficial atual. A opção Portainer não abrange a criação do MongoDB.

## Pré-requisitos

Exige MongoDB compatível com a CPU, domínio TLS, secrets distintos, configuração
de provedores e política de cadastro. Recursos crescem com anexos, RAG, agentes,
execução de código e número de usuários; 512 MB de catálogo não representa a
stack oficial completa.

## Fluxo seguro

Não recomende produção com o script atual. Fixe release, remova a porta pública,
use banco e usuário dedicados, feche cadastro e defina secrets independentes.
Decida conscientemente se Meilisearch, RAG API e painel administrativo serão
implantados, em stacks isoladas e com persistência própria.

## Primeiro acesso e integrações

Crie primeiro administrador em janela controlada, feche registro e conecte um
provedor de teste com limite baixo. OpenAI, Ollama e APIs compatíveis podem ser
configurados sem expor a chave na conversa ou no navegador além do necessário.

## Backup, atualização e rollback

Faça backup consistente do MongoDB e dos volumes de anexos e imagens. Preserve
configuração e chaves fora da imagem. Antes de atualizar, leia mudanças de
schema, fixe versão e teste restauração; `latest` impede rollback reproduzível.

## Validação

Valide login, registro fechado, MongoDB, upload, provedor, streaming e limites.

## Diagnóstico

Separe erro da interface, banco, endpoint, autenticação e modelo. Nunca envie
prompts de cliente, conversas, anexos ou chaves ao Assistente.

## Riscos e limites

Risco crítico por tag móvel, porta publicada, cadastro aberto, MongoDB root
compartilhado e arquitetura incompleta em relação ao deploy oficial. O
Assistente deve explicar essas diferenças antes de orientar qualquer instalação.
