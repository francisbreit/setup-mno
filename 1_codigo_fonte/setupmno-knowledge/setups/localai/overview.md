---
{
  "schemaVersion": 1,
  "documentId": "setup-localai-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "95d080ce347b65da1599b702d8486073f285b32ae800ce8e7b19ce8f1f46b7b3",
  "documentType": "setup",
  "title": "LocalAI no Setup MNO",
  "setupId": "localai",
  "setupVersion": "7.28.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["localai", "llm", "inferencia-local", "openai-compatible", "modelos"],
  "sources": [
    {"sourceId":"localai-installer","title":"Instalador LocalAI","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/localai.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"localai-quickstart","title":"Quickstart oficial do LocalAI","sourceType":"official-documentation","location":"https://localai.io/basics/getting_started/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"localai-containers","title":"Imagens oficiais do LocalAI","sourceType":"official-documentation","location":"https://localai.io/basics/container/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"localai-models","title":"Gerenciamento oficial de modelos LocalAI","sourceType":"official-documentation","location":"https://localai.io/models/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# LocalAI no Setup MNO

## Quando usar

Use para inferência local por API compatível com OpenAI quando privacidade e
controle justificam custo de CPU, RAM, disco ou GPU. Não escolha antes de medir
modelo, quantização, contexto, latência e throughput no hardware real.

## Arquitetura no Setup MNO

O instalador usa uma tag móvel da imagem oficial LocalAI, quatro CPUs, 4 GB e volumes de modelos
e dados. Publica 8080 no host e por HTTPS, sem chave de API nem autenticação de
usuários. Não coleta modelo durante o fluxo; ao final sugere comandos manuais que
pressupõem nome de contêiner estável, o que não é garantido no Swarm.

## Pré-requisitos

Verifique arquitetura, instruções da CPU, espaço para modelos e memória além do
tamanho do arquivo. GPU exige imagem e dispositivos específicos. Modelos com
licença ou acesso restrito exigem aprovação e credencial própria.

## Fluxo seguro

Bloqueie produção na distribuição atual. Fixe versão e variante de hardware,
habilite chave de API ou autenticação multiusuário, remova a porta pública e
homologue um modelo permitido. Downloads e comandos de modelo devem virar fluxo
determinístico com confirmação, hash, licença e limite de recursos.

## Primeiro acesso e integrações

Após proteção, confirme `/readyz`, liste modelos e faça uma inferência fictícia.
n8n, Open WebUI, LibreChat e aplicações compatíveis podem usar a URL interna
`/v1`; cada consumidor deve possuir chave própria quando o modo permitir.

## Backup, atualização e rollback

Preserve configurações e inventário de modelos; não trate pesos baixados como
única cópia de dados importantes. Fixe imagem e modelo, meça antes da troca e
mantenha versão anterior. Backups não podem redistribuir modelos contra a licença.

## Validação

Valide health, autenticação, modelo, tokenizer, memória, tempo de carregamento,
contexto e streaming.

## Diagnóstico

Separe erro do runtime, hardware, download e cliente. Não envie prompts, respostas,
tokens de repositório ou arquivos privados ao Assistente.

## Riscos e limites

Risco crítico porque uma API capaz de consumir recursos e processar dados fica
publicada sem autenticação, usando tag móvel e modelo não homologado. O rótulo de
4 GB não garante que qualquer modelo escolhido caiba ou responda adequadamente.
