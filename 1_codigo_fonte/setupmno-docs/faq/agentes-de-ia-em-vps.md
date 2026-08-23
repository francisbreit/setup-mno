# FAQ — agentes de IA em VPS

- Estado: `draft`
- Atualizado em: 2026-08-23
- Publicação no Help: futura, após revisão editorial

## Posso iniciar Codex ou Claude Code em `/root`?

Não é recomendado. Se o processo estiver como root, o sistema operacional pode
permitir leitura e alteração de arquivos críticos. O diretório de trabalho não
substitui usuário sem privilégios, sandbox e permissões restritas.

## Posso adicionar o usuário da IA ao grupo `docker`?

Não em produção. Controlar o daemon Docker normalmente concede capacidade
equivalente a root no host.

## A IA poderá instalar aplicações fora do catálogo?

O desenho prevê que ela prepare um candidato em workspace isolado. O candidato
deverá passar por políticas, SBOM, homologação e revisão humana antes de poder
ser incorporado ao Setup MNO. A IA não publicará diretamente.

## Posso enviar logs inteiros para uma IA?

Não. Logs podem conter hostnames, IPs, tokens, URLs privadas, e-mails e dados de
clientes. O AI Safe Mode deverá trabalhar com coleta permitida e sanitização
antes do envio.

## A IA poderá corrigir o servidor automaticamente?

Não na primeira arquitetura. Ela poderá explicar e propor. Operações reais
continuarão em fluxos determinísticos do Setup MNO e exigirão confirmação.

## O modo seguro será exclusivo de planos pagos?

Bloqueios críticos, avisos e proteção de dados devem existir para todos os
planos. Capacidades avançadas podem variar por plano. Criação de políticas,
exceções, homologação e promoção canônica permanecem exclusivas do mantenedor
PRO MASTER.

## Escalar réplicas resolve qualquer gargalo?

Não. Serviços stateless podem se beneficiar. Bancos, filas e volumes exigem
estratégia própria de consistência, replicação, backup e recuperação.

## O Setup MNO garante que nunca haverá falha?

Não. O objetivo é reduzir risco, tornar decisões auditáveis, bloquear padrões
perigosos e oferecer recuperação testável. Nenhuma ferramenta elimina riscos
de software, operador, infraestrutura ou fornecedor.
