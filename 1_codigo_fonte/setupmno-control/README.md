# Setup MNO Control Center

Painel web oficial do Setup MNO. O projeto é compilado localmente durante a
instalação e executado em três stacks independentes:

- `web`: autenticação, interface responsiva, catálogo, auditoria e proxy do terminal;
- `agent`: inventário somente leitura do Docker Swarm e métricas do host;
- `terminal`: sessão isolada do instalador original, acessível apenas pelo painel.

O agente não oferece endpoints de escrita. O único componente com acesso ao
instalador original é o terminal, protegido pela autenticação e pela sessão do
painel.

## Sincronização

Depois de alterar o painel ou o catálogo:

```bash
./1_codigo_fonte/setupmno-control/generate-installers.sh
```

O comando recria mecanicamente os scripts `setupmno_control.sh` de x86 e ARM
com o mesmo bundle de fontes.
