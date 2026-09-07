---
{
  "schemaVersion": 1,
  "documentId": "setup-langflow-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "e03825284684301c96ffc8f6f38db75b67d541c1cb3d1e081ee47f3f851f53ea",
  "documentType": "setup",
  "title": "Langflow no Setup MNO",
  "setupId": "langflow",
  "setupVersion": "7.45.0",
  "architectures": ["amd64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["langflow", "llm", "agentes", "low-code", "postgresql"],
  "sources": [
    {"sourceId":"langflow-installer","title":"Instalador Langflow","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/langflow.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"langflow-docker","title":"Deploy oficial do Langflow no Docker","sourceType":"official-documentation","location":"https://docs.langflow.org/deployment-docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"langflow-architecture","title":"Arquitetura oficial de deployment do Langflow","sourceType":"official-documentation","location":"https://docs.langflow.org/deployment-architecture","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Langflow no Setup MNO

## Quando usar

Use como ambiente visual para construir e testar fluxos de IA. A documentação
atual distingue o IDE visual do runtime de produção sem interface; escolha o
modo conforme quem edita os fluxos e quem apenas consome endpoints.

## Arquitetura no Setup MNO

O catálogo declara somente amd64. O instalador cria uma réplica do IDE Langflow
1.1.3, volume de dados e banco lógico no PostgreSQL base, com rota na porta
interna 7860. Login automático é desativado e a conta inicial é coletada. A
versão distribuída está muito atrás da linha oficial atual.

## Pré-requisitos

Exige PostgreSQL saudável, domínio, ao menos a capacidade do catálogo e folga
para modelos ou serviços externos. Defina se o servidor hospedará somente o IDE
ou também endpoints de produção, e mantenha esses papéis separados quando a
carga ou o risco justificar.

## Fluxo seguro

O Instalador Seguro coleta domínio, usuário, senha e modo Portainer ou Docker,
cria banco e volume e publica o IDE. Antes de uso real, atualize e homologue a
imagem, confirme autenticação e restrinja o editor. Não habilite auto-login em
uma instância pública.

## Primeiro acesso e integrações

Crie um fluxo descartável com provedor de teste, sem dados pessoais. Para uma
aplicação, exporte ou versione o fluxo e avalie o runtime backend-only. LiteLLM,
Qdrant, OpenAI, Ollama e APIs externas exigem chaves separadas e escopo mínimo.

## Backup e atualização

Preserve o volume do Langflow e o banco PostgreSQL, exporte fluxos críticos e
registre a imagem. A documentação oficial recomenda volumes persistentes e
PostgreSQL para atualização. Teste migrações e restauração antes de promover.

## Validação

Confirme login, persistência, criação e execução de fluxo, chamada autenticada
ao endpoint, comportamento após reinício e falha controlada do provedor. Para
runtime, valide também concorrência, timeout e isolamento do editor.

## Riscos e limites

O script ARM existe, mas a entrada canônica do catálogo é somente amd64 e não
autoriza recomendação ARM. A imagem 1.1.3 é obsoleta diante da documentação
atual; integração ou componente recente pode não existir. Exija modernização e
homologação antes de uso de produção.

## Diagnóstico

Separe rota, login, banco, volume, componente do fluxo e provedor. Compare a
versão do componente com a imagem efetiva. Não envie arquivo de fluxo com
segredos, credenciais de modelo ou payloads de clientes ao Assistente.
