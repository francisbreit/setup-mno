---
{
  "schemaVersion": 1,
  "documentId": "setup-openobserve-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a3599aed1d73c71ad4c526f77d1d6cac52db43b1605b7a7f541329cb6458ac9d",
  "documentType": "setup",
  "title": "OpenObserve no Setup MNO",
  "setupId": "openobserve",
  "setupVersion": "7.48.24",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-13",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["openobserve", "observabilidade", "logs", "metricas", "traces", "opentelemetry"],
  "sources": [
    {"sourceId":"openobserve-installer","title":"Instalador OpenObserve PRO","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/openobserve.sh","license":"project-internal","verifiedAt":"2026-08-13"},
    {"sourceId":"openobserve-getting-started","title":"Getting Started with OpenObserve","sourceType":"official-documentation","location":"https://openobserve.ai/docs/getting-started/","license":"documentation-reference","verifiedAt":"2026-08-13"},
    {"sourceId":"openobserve-environment","title":"OpenObserve Environment Variables","sourceType":"official-documentation","location":"https://openobserve.ai/docs/administration/configuration/environment-variables/","license":"documentation-reference","verifiedAt":"2026-08-13"},
    {"sourceId":"openobserve-releases","title":"OpenObserve Releases","sourceType":"official-documentation","location":"https://github.com/openobserve/openobserve/releases/tag/v0.90.3","license":"documentation-reference","verifiedAt":"2026-08-13"}
  ],
  "homologation": {
    "verifiedAt": "2026-08-13",
    "verifiedPorts": [5080],
    "verifiedImages": [
      "public.ecr.aws/zinclabs/openobserve:v0.90.3@sha256:f77856199bff2097e0355d66e59d5792064ff8ff831ea5f580b3650fa5457136"
    ]
  }
}
---
# OpenObserve no Setup MNO

## Quando usar

Use o OpenObserve para centralizar logs, métricas e traces, criar dashboards,
pesquisar telemetria e configurar alertas. Ele é uma alternativa unificada a
combinações maiores de ferramentas de observabilidade e aceita integrações
compatíveis com OpenTelemetry, Prometheus e APIs de ingestão documentadas.

## Arquitetura no Setup MNO

O instalador cria uma única stack em modo local de nó único. Metadados, WAL,
índices e streams permanecem em um diretório exclusivo do host. O serviço usa
as redes externa e interna, mas a porta 5080 não é publicada no host. O acesso
externo ocorre exclusivamente pelo Traefik ou pelo Cloudflare Tunnel.

A imagem oficial é fixada por versão e digest multi-arquitetura. O processo
executa como UID 65532, com filesystem raiz somente leitura, todas as
capabilities removidas e privilégio adicional bloqueado. A telemetria anônima,
o Swagger e o servidor de Actions ficam desativados por padrão.

## Primeiro acesso e credenciais

O usuário informa o e-mail e uma senha forte durante a instalação. Como a
imagem oficial não oferece suporte documentado a variável com sufixo `_FILE`,
essas credenciais entram apenas no primeiro start. Depois de confirmar a API e
a persistência, o instalador reconcilia a stack sem as variáveis de bootstrap e
valida que a senha não permanece na especificação do serviço nem no YAML final.

O administrador acessa o domínio configurado e entra com o e-mail e a senha
definidos no instalador. Essas credenciais continuam registradas internamente
na base persistente do próprio OpenObserve; removê-las do serviço não altera o
login já criado.

## Pré-requisitos

Exige Docker Swarm ativo, redes externa e interna do Setup MNO, domínio válido,
pelo menos 4 GB de RAM no servidor e espaço em disco compatível com ingestão e
retenção. O perfil de domínio deve possuir as credenciais necessárias ao modo
Traefik ou Cloudflare Tunnel escolhido durante a instalação.

## Riscos e limites

O limite configurado é de dois CPUs e 2 GB de RAM, com reserva de 256 MB. Esse
perfil atende uma implantação inicial de nó único, mas o consumo real depende
do volume de ingestão, cardinalidade, retenção, consultas e compactação. Espaço
em disco deve ser dimensionado pela taxa diária de dados e pelo período de
retenção, não somente pelo tamanho inicial do container.

Para alta disponibilidade ou grande volume, use a arquitetura cluster oficial,
que exige projeto específico de metadados, armazenamento de objetos, filas e
funções distribuídas. A instalação PRO atual não deve ser apresentada como HA.

## Fluxo seguro

Mantenha HTTPS e restrinja o domínio administrativo com Cloudflare Access
quando disponível. Não reutilize a conta root em agentes de coleta; crie
usuários ou tokens de ingestão com o menor privilégio aceito pela integração.
Evite enviar senhas, tokens e dados pessoais nos próprios logs observados.

As APIs de ingestão fazem parte da aplicação acessível pelo mesmo domínio. A
ausência de porta publicada reduz a exposição direta, mas não substitui rate
limit, autenticação, retenção adequada e controle dos clientes autorizados.

## Validação

O instalador exige Docker Swarm ativo, redes externa e interna e credenciais do
perfil de domínio. Ele valida ambas as arquiteturas no manifesto oficial,
inicialização não-root, endpoint interno `/healthz`, criação de arquivos
persistentes, reconciliação sem credenciais e réplica 1/1 antes de configurar o
DNS e a rota pública. A consulta interna usa um serviço efêmero do Swarm,
restrito a 64 MB, filesystem somente leitura e sem capabilities; isso preserva
a validação nas redes overlay não anexáveis e o serviço auxiliar é removido no
sucesso, na falha e no rollback.

## Diagnóstico

Se o painel não abrir, verifique réplica, logs do serviço, resolução DNS e rota
do Tunnel ou Traefik. Se a réplica reiniciar durante ingestão ou compactação,
compare uso de memória e disco com os limites antes de alterar a configuração.
Uma resposta saudável da API sem dados normalmente indica ausência ou erro de
autenticação no agente de coleta, intervalo de tempo incorreto ou stream errado.

## Backup, atualização e rollback

Faça backup consistente de todo o diretório persistente antes de atualizar. A
stack final é editável no Portainer quando essa modalidade é selecionada, mas a
imagem deve continuar fixada por digest até que uma nova versão seja validada.
Em caso de falha durante a instalação, o rollback remove somente a stack, o
diretório e o YAML exclusivos da execução e restaura DNS e Tunnel alterados.

Para migração ou mudança de arquitetura, preserve os dados, documente a versão
de origem e teste a restauração em instância isolada. Não apague WAL, índices ou
banco SQLite para corrigir sintomas sem backup e diagnóstico conclusivo.
