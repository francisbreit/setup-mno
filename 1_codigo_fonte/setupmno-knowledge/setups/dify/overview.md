---
{
  "schemaVersion": 1,
  "documentId": "setup-dify-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "6aa55557781a25da77ef9dc735c6fb57189445cf8f4cfb54f77b86c1c0eb0e08",
  "documentType": "setup",
  "title": "Dify no Setup MNO",
  "setupId": "dify",
  "setupVersion": "7.48.26",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["dify", "llm", "rag", "agentes", "weaviate", "redis", "minio"],
  "sources": [
    {"sourceId":"dify-installer","title":"Instalador Dify","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/dify.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"dify-docker-readme","title":"Deploy oficial do Dify com Docker","sourceType":"official-documentation","location":"https://github.com/langgenius/dify/blob/main/docker/README.md","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"dify-releases","title":"Releases oficiais do Dify","sourceType":"official-documentation","location":"https://github.com/langgenius/dify/releases","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Dify no Setup MNO

## Quando usar

Use para projetar aplicações de IA com workflows, agentes, bases RAG e acesso a
provedores de modelos. O produto não fornece modelos nem elimina a necessidade
de governança sobre dados, custos, permissões, retenção e conteúdo enviado aos
provedores.

## Arquitetura no Setup MNO

O instalador atual usa o PostgreSQL base, Redis e Weaviate dedicados, storage S3
em MinIO compartilhado ou criado durante o fluxo, e serviços separados de API,
worker, agendador, web e sandbox. As rotas web e API recebem domínios distintos.
Essa composição é menor que a referência oficial atual e usa várias tags
móveis; não se deve presumir equivalência entre elas.

## Pré-requisitos

Exige pelo menos a capacidade indicada no catálogo, folga adicional para
indexação e workers, dois domínios, SMTP, storage S3, PostgreSQL saudável e
credenciais de provedores configuradas somente depois do deploy. Defina antes
quais dados podem entrar em prompts, documentos e plugins.

## Fluxo seguro

O Instalador Seguro coleta domínios, SMTP e modo Portainer ou Docker, cria banco
e substacks antes da aplicação. Na versão atual há senha inicial literal e
diferenças relevantes em relação ao Compose oficial, incluindo serviços de
plugins e proteção SSRF. Por isso a promoção automática está bloqueada até o
instalador ser modernizado e homologado isoladamente.

## Primeiro acesso e integrações

Depois de uma correção homologada, o primeiro teste deve usar conta nova, modelo
de baixo risco e documento fictício. Integre LiteLLM, OpenAI, Ollama, SearXNG,
Firecrawl ou APIs apenas com chaves exclusivas, limites, allowlists e escopo
mínimo. Nunca copie chave de provedor ou documento de cliente no Assistente.

## Backup e atualização

O plano precisa cobrir PostgreSQL, storage do Dify, bucket S3 e Weaviate. Redis
é estado operacional, mas pode afetar tarefas em andamento. Leia as notas de
release, preserve variáveis e execute migrações previstas oficialmente antes de
trocar imagens. Tags `latest` impedem rollback determinístico.

## Validação

Valide saúde de todos os serviços, login, criação de workflow, chamada de
modelo, ingestão e recuperação de documento fictício, execução do sandbox,
worker e envio SMTP. Uma página web aberta não comprova RAG nem filas.

## Riscos e limites

Risco crítico na versão distribuída: composição desatualizada, imagens móveis,
credencial inicial literal e ausência de componentes de segurança presentes na
referência atual. O Assistente deve explicar o bloqueio e não recomendar deploy
de produção até existir correção específica e evidência de homologação.

## Diagnóstico

Separe falhas de rota, banco, Redis, Weaviate, S3, sandbox, worker e provedor.
Use réplicas e códigos sanitizados; não exponha prompts, documentos, chaves,
SMTP, URLs privadas nem conteúdo recuperado.
