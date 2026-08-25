---
{
  "schemaVersion": 1,
  "documentId": "setup-phpmyadmin-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "7e432d29ccdec24f35a8fa248027322cc25fef4567401706488adde8a82ce545",
  "documentType": "setup",
  "title": "phpMyAdmin no Setup MNO",
  "setupId": "phpmyadmin",
  "setupVersion": "7.33.5",
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
    "phpmyadmin",
    "mysql",
    "mariadb",
    "administracao"
  ],
  "sources": [
    {
      "sourceId": "phpmyadmin-installer",
      "title": "Instalador phpMyAdmin",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/pma.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "phpmyadmin-docs",
      "title": "Documentação oficial do phpMyAdmin",
      "sourceType": "official-documentation",
      "location": "https://docs.phpmyadmin.net/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "phpmyadmin-docker",
      "title": "Imagem oficial Docker do phpMyAdmin",
      "sourceType": "official-documentation",
      "location": "https://hub.docker.com/_/phpmyadmin",
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
# phpMyAdmin no Setup MNO

## Quando usar

Use para administração visual pontual de MySQL ou MariaDB por operador autorizado. Não exponha permanentemente uma interface administrativa quando cliente SQL ou automação auditável for suficiente.

## Arquitetura no Setup MNO

O instalador publica a imagem oficial do phpMyAdmin e a conecta ao banco definido pelo fluxo. A interface não armazena os dados, mas recebe credenciais com poder direto sobre eles.

## Pré-requisitos

O catálogo declara cerca de 2 GB de RAM, mas o consumo dominante pode estar no banco administrado; meça interface e banco separadamente.

Exige domínio HTTPS, banco acessível apenas pela rede necessária, conta dedicada e política de acesso. Evite login root e limite upload, sessão e origem.

## Fluxo seguro

Use conta de menor privilégio, autenticação adicional no proxy e acesso temporário. Não cole SQL, dumps, nomes de clientes ou credenciais no Assistente.

## Primeiro acesso e integrações

Entre com banco de teste e confirme que a conta só vê os schemas autorizados. Não salve senha no navegador compartilhado.

## Backup e atualização

O backup é do banco, não da interface. Gere dump consistente, teste restore e preserve configuração adicional antes de atualizar a imagem.

## Validação

Confirme HTTPS, autenticação, menor privilégio, timeout, restrição de hosts e execução de consulta inofensiva. Teste que usuário restrito não acessa outros bancos.

## Riscos e limites

Uma falha de sessão ou credencial concede leitura e escrita direta no banco. Root remoto, tag flutuante e exposição pública tornam o risco crítico.

## Diagnóstico

Separe proxy, sessão, credencial, rede, TLS do banco e privilégio SQL. Use schema e conta fictícios para reproduzir.
