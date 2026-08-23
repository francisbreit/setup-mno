# Resposta a incidentes do Setup MNO

- Estado: `implemented`
- Atualizado em: 2026-08-23
- Público: mantenedor PRO MASTER e autores do futuro Help
- Ambientes: Debian, Ubuntu, WSL2, Docker Swarm, Traefik e Cloudflare

## Resumo para leigos

Durante um incidente, velocidade sem controle pode ampliar o dano. O objetivo
inicial é estabilizar o serviço e preservar fatos. Só depois se corrige a causa.
Um bom registro permite saber o que aconteceu, quem aprovou a ação e se o
resultado realmente melhorou.

## Objetivo

Oferecer um processo comum para indisponibilidade, degradação, falha de deploy,
perda de dados ou suspeita de segurança.

## Severidade inicial

- **Crítica:** perda ou exposição de dados, comprometimento, indisponibilidade
  ampla sem alternativa.
- **Alta:** serviço importante indisponível ou degradação severa.
- **Média:** falha parcial com alternativa conhecida.
- **Baixa:** impacto pequeno, cosmético ou restrito a homologação.

A severidade pode mudar quando surgem fatos novos.

## Processo

1. **Declarar:** horário, impacto, escopo e responsável pela coordenação.
2. **Preservar:** registrar baseline e primeira falha antes de reinícios.
3. **Estabilizar:** reduzir impacto com a menor ação reversível autorizada.
4. **Diagnosticar:** separar fatos, hipótese e lacunas.
5. **Planejar:** impacto, pré-condições, aprovação, rollback e validação.
6. **Executar:** somente operação versionada e permitida.
7. **Verificar:** comparar métricas e fluxo funcional com o estado anterior.
8. **Encerrar:** registrar causa, duração, ações e pendências.
9. **Aprender:** corrigir controle, documentação e teste que permitiram a falha.

## Registro mínimo

```text
Incidente: identificador fictício
Início e timezone:
Impacto observado:
Serviços afetados:
Última mudança conhecida:
Fatos coletados:
Hipótese e confiança:
Ação aprovada:
Rollback preparado:
Resultado e evidência:
Dados sanitizados por:
```

## Quando parar

Interrompa a intervenção e escale quando houver suspeita de invasão, risco de
perda definitiva, backup desconhecido, alvo ambíguo, ausência de quorum ou
necessidade de credencial fora do processo autorizado. “Continuar tentando” não
é estratégia de recuperação.

## Limites e segurança

- Não cole logs brutos em chatbot público.
- Não execute comandos sugeridos por IA sem entender alvo, impacto e rollback.
- Não apague recursos para reduzir ruído.
- Não atribua causa raiz sem evidência; registre como hipótese.
- Não altere Cloudflare, Swarm e aplicação ao mesmo tempo.
- Ações de contenção de segurança exigem coordenação humana específica.

## Pós-incidente sem caça aos culpados

O relatório deve explicar como o sistema permitiu a falha e qual controle será
melhorado. Itens úteis incluem detecção, documentação, backup, validação,
permissões, dependências, comunicação e tempo de recuperação.

## Fontes oficiais

- [NIST SP 800-61 Rev. 3 — Incident Response](https://csrc.nist.gov/pubs/sp/800/61/r3/final)
- [Docker Swarm administration guide](https://docs.docker.com/engine/swarm/admin_guide/)
- [Cloudflare troubleshooting](https://developers.cloudflare.com/support/troubleshooting/)

## Publicação futura no Help

Criar um modo “estou com incidente agora” que priorize checklist curto,
cronômetro, preservação de evidência e contatos. Ele não deve oferecer execução
automática nem substituir o plano de recuperação.
