---
{
  "schemaVersion": 1,
  "documentId": "setup-glpi-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "70e4b44b9407144c3a5ed951d17368b8340b277c576ba35ffeb3508a8308698f",
  "documentType": "setup",
  "title": "GLPI no Setup MNO",
  "setupId": "glpi",
  "setupVersion": "7.7.36",
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
    "glpi",
    "inventario",
    "helpdesk",
    "ativos"
  ],
  "sources": [
    {
      "sourceId": "glpi-installer",
      "title": "Instalador GLPI",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/glpi.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "glpi-official-1",
      "title": "Documentação oficial de GLPI",
      "sourceType": "official-documentation",
      "location": "https://help.glpi-project.org/tutorials/procedures/install_glpi",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "glpi-official-2",
      "title": "Documentação oficial de GLPI",
      "sourceType": "official-documentation",
      "location": "https://help.glpi-project.org/documentation/modules/configuration/plugins",
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
# GLPI no Setup MNO

## Quando usar

Use para gerenciar ativos, inventário, chamados e serviços de TI. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador está limitado a amd64 e entrega GLPI com banco conforme o script atrás do proxy. Plugins e agentes ampliam a superfície e precisam ser tratados como componentes versionados.

## Pré-requisitos

Exige domínio HTTPS, banco, política de perfis, inventário autorizado e estratégia de agentes. Confirme versão suportada de GLPI, PHP e banco antes de atualizar.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Conclua o assistente, troque qualquer credencial padrão, crie perfis por função e teste um ativo e chamado fictícios. Instale somente plugins compatíveis e necessários.

## Backup e atualização

Preserve banco e diretórios de configuração, documentos, plugins e marketplace. Atualização requer backup, verificação de compatibilidade de plugins e ensaio de migração.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Inventário pode conter dados sensíveis de pessoas e dispositivos. Plugins incompatíveis quebram atualização. O Setup não autoriza descoberta indiscriminada nem coleta fora do escopo aprovado.

## Diagnóstico

Diferencie aplicação, banco, permissões de volume, cron, agente e plugin. Reproduza com ativo fictício e sanitize nomes, IPs, seriais, usuários e anexos.
