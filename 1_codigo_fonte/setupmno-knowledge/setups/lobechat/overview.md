---
{
  "schemaVersion": 1,
  "documentId": "setup-lobechat-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "d851d82f5a4424ec9e801d4a7d656201d9814407533c7d5aee1b8d9f518ee7aa",
  "documentType": "setup",
  "title": "LobeChat no Setup MNO",
  "setupId": "lobechat",
  "setupVersion": "7.48.12",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "lobechat",
    "ia",
    "chat",
    "llm"
  ],
  "sources": [
    {
      "sourceId": "lobechat-installer",
      "title": "Instalador LobeChat",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/lobechat.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "lobechat-official-1",
      "title": "Documentação oficial de LobeChat",
      "sourceType": "official-documentation",
      "location": "https://lobehub.com/docs/self-hosting/platform/docker",
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
# LobeChat no Setup MNO

## Quando usar

Use para oferecer uma interface web para conversar com modelos e agentes de IA. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador entrega LobeChat por uma rota do Setup e injeta as configurações declaradas no script. Dependendo do modo, histórico, autenticação e arquivos podem residir no navegador ou em serviços externos.

## Pré-requisitos

Exige provedor LLM, chave segura, código de acesso ou autenticação, domínio HTTPS e política para prompts e arquivos. Defina modelos permitidos e orçamento.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Proteja a instância antes da exposição, configure um modelo de teste e valide streaming sem enviar dados reais. Não habilite plugins ou ferramentas de terceiros sem revisão de permissões.

## Backup e atualização

Preserve configuração e dados persistentes conforme o modo escolhido. Registre modelo, variáveis e versão; uma troca de imagem deve ser ensaiada sem reutilizar a chave produtiva.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Prompts podem sair da VPS para o provedor. A resposta pode errar e plugins ampliam o risco. Tag flutuante e ausência de senha são incompatíveis com uma exposição segura.

## Diagnóstico

Separe autenticação, frontend, rota e provedor. Verifique erro HTTP e limite do modelo com prompt fictício; nunca copie chave, conversa, arquivo ou resposta privada ao Assistente.
