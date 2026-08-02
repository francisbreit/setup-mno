---
{
  "schemaVersion": 1,
  "documentId": "setup-formbricks-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "1712264affc01f13a37e0d6b0e363497247201056d3cef0f742524ca026d9082",
  "documentType": "setup",
  "title": "Formbricks no Setup MNO",
  "setupId": "formbricks",
  "setupVersion": "7.2.9",
  "architectures": [
    "amd64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "formbricks",
    "formularios",
    "pesquisa",
    "feedback"
  ],
  "sources": [
    {
      "sourceId": "formbricks-installer",
      "title": "Instalador Formbricks",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/formbricks.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "formbricks-official-1",
      "title": "Documentação oficial de Formbricks",
      "sourceType": "official-documentation",
      "location": "https://formbricks.com/docs/self-hosting/overview",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "formbricks-official-2",
      "title": "Documentação oficial de Formbricks",
      "sourceType": "official-documentation",
      "location": "https://formbricks.com/docs/self-hosting/setup/docker",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Formbricks no Setup MNO

## Quando usar

Use para coletar pesquisas, feedback de produto e formulários em ambiente self-hosted. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador atual do Setup entrega uma composição anterior e está limitado a amd64. A documentação oficial da linha atual inclui serviços adicionais e requisitos de cache e armazenamento, portanto a arquitetura instalada deve ser comparada antes de atualizar.

## Pré-requisitos

Exige HTTPS, banco, segredos de sessão e criptografia, política de consentimento e retenção. Verifique se o script cobre a composição exigida pela versão atual.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie o administrador, restrinja cadastro e publique uma pesquisa fictícia. Valide webhook com destino de teste e confirme que respostas e uploads obedecem à política de privacidade.

## Backup e atualização

Preserve banco, armazenamento de arquivos e segredos necessários à leitura dos dados. Antes de migrar versão principal, siga a documentação e ensaie o restore em cópia isolada.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Homologação de produção bloqueada até alinhar o instalador à arquitetura oficial atual. Respostas podem conter dados pessoais e links públicos precisam de controles contra abuso.

## Diagnóstico

Separe rota, autenticação, banco, cache, serviços analíticos e arquivos. Reproduza com formulário fictício e não envie respostas reais ou segredos ao Assistente.
