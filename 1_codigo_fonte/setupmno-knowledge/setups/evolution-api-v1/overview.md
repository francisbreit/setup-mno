---
{
  "schemaVersion": 1,
  "documentId": "setup-evolution-api-v1-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "1e0263a03bf0e69280b8d0d736878c5744a5128b4f50effa15cc428f62ea858f",
  "documentType": "setup",
  "title": "Evolution API v1 no Setup MNO",
  "setupId": "evolution-api-v1",
  "setupVersion": "7.36.0",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "evolution-api",
    "whatsapp",
    "legado",
    "v1"
  ],
  "sources": [
    {
      "sourceId": "evolution-api-v1-installer",
      "title": "Instalador Evolution API v1",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/evolutionapi.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "evolution-api-v1-official-1",
      "title": "Documentação oficial de Evolution API v1",
      "sourceType": "official-documentation",
      "location": "https://doc.evolution-api.com/",
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
# Evolution API v1 no Setup MNO

## Quando usar

Use para manter visibilidade sobre uma instalação histórica da Evolution API v1 durante migração. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador v1 usa a composição antiga da Evolution API com banco e cache definidos pelo script e rota externa. Ela permanece separada do setup v2 e não deve ser confundida com a linha atual.

## Pré-requisitos

Exige backup, inventário de instâncias, versão exata, janela de manutenção e plano de migração para versão suportada. Use número de teste e confirme requisitos atuais na documentação oficial.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Não crie uma nova implantação v1 por padrão. Em legado autorizado, valide exportação, webhooks e credenciais e faça prova de migração isolada antes de tocar no serviço original.

## Backup e atualização

Preserve banco, cache, sessões e configuração de webhooks. O rollback deve restaurar a mesma versão e o mesmo schema; uma cópia de arquivos sem sessão validada não comprova recuperação.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Promoção bloqueada por ser uma linha legada. Contratos, bibliotecas do WhatsApp e endpoints podem divergir da v2. A conexão pode não ser oficial e está sujeita a bloqueio pelo provedor.

## Diagnóstico

Confirme que o incidente é realmente v1, depois isole rede, banco, cache, sessão e webhook. Não recomende parâmetros de v2 para v1 nem exponha telefone, QR, token ou mensagens.
