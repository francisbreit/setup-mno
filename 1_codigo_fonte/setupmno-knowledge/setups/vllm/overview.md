---
{
  "schemaVersion": 1,
  "documentId": "setup-vllm-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "92f5225999ca031d584971c4d98d97cfbf145d61037b9694bf19a63460b8fd15",
  "documentType": "setup",
  "title": "vLLM no Setup MNO",
  "setupId": "vllm",
  "setupVersion": "7.7.19",
  "architectures": ["amd64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["vllm", "llm", "inferencia", "openai-compatible", "cpu"],
  "sources": [
    {"sourceId":"vllm-installer","title":"Instalador vLLM","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/vllm.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"vllm-docker","title":"Imagem Docker oficial do vLLM","sourceType":"official-documentation","location":"https://docs.vllm.ai/en/latest/deployment/docker/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"vllm-cpu","title":"Instalação CPU oficial do vLLM","sourceType":"official-documentation","location":"https://docs.vllm.ai/en/stable/getting_started/installation/cpu/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"vllm-server","title":"Servidor compatível com OpenAI do vLLM","sourceType":"official-documentation","location":"https://docs.vllm.ai/en/latest/serving/openai_compatible_server/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# vLLM no Setup MNO

## Quando usar

Use para servir LLMs com alto throughput quando o hardware e o modelo forem
homologados. Para CPU pequena, LocalAI ou Ollama podem ser mais simples; vLLM é
mais conhecido por inferência acelerada e exige planejamento de memória.

## Arquitetura no Setup MNO

O script usa a tag móvel da imagem oficial de CPU do vLLM, quatro CPUs, cache compartilhado e
memória igual ao KV cache escolhido. Publica o servidor por HTTPS sem API key.
O mesmo YAML é distribuído em ARM, mas a documentação oficial usa tag específica
`latest-arm64`; por isso esta entrada só declara amd64 até homologação ARM.

## Pré-requisitos

O modelo pode exigir token do repositório, aceite de licença, instruções de CPU,
RAM e espaço muito superiores ao cache. Shared memory e afinidade também afetam
o runtime. O limite total deve incluir pesos, KV cache e overhead do processo.

## Fluxo seguro

Bloqueie produção. Fixe versão, modelo e revisão, implemente autenticação, remova
exposição pública e valide licença e hash. Para ARM, use a imagem indicada pela
documentação e teste no hardware alvo; não presuma compatibilidade pelo catálogo.

## Primeiro acesso e integrações

Após proteção, verifique `/v1/models`, execute prompt fictício com saída curta e
meça latência e memória. LiteLLM, Open WebUI e aplicações compatíveis podem usar
o endpoint interno com chave exclusiva.

## Backup, atualização e rollback

Cache de pesos pode ser reconstruído, mas preserve configuração, revisão exata e
licenças. Atualização de runtime ou modelo muda qualidade e consumo; mantenha a
imagem anterior e execute canários antes de trocar tráfego.

## Validação

Valide arquitetura, instruções, modelo, tokenizer, memória, shared memory,
autenticação, streaming e concorrência.

## Diagnóstico

Separe falha de download, runtime, modelo e cliente. Não envie tokens de
repositório, prompts ou saídas privadas ao Assistente.

## Riscos e limites

Risco crítico por API pública sem autenticação, tag móvel, memória subestimada e
imagem incorreta para ARM. O Assistente não deve confirmar ARM nem capacidade de
um modelo sem evidência do servidor e do artefato exato.
