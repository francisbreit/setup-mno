# Setup MNO Control Center

Painel web oficial do Setup MNO. O projeto é compilado localmente durante a
instalação e executado em três stacks independentes:

- `web`: autenticação, interface responsiva, catálogo, auditoria e proxy do terminal;
- `agent`: inventário somente leitura do Docker Swarm, métricas do host e leitura
  validada do manifesto e catálogo runtime;
- `terminal`: sessão isolada do instalador original, acessível apenas pelo painel.

O agente não oferece endpoints de escrita nem uma API genérica de arquivos ou
comandos. O único componente com acesso ao
instalador original é o terminal, protegido pela autenticação e pela sessão do
painel.

## Sincronização

O Setup publica atomicamente em `/root/SetupLowCodeMno/.control/`:

- `release.json`: versão instalada, arquitetura, schema, quantidade e SHA-256;
- `catalog.json`: catálogo correspondente à release.

Ao carregar a página, retornar à aba, usar a atualização manual ou a cada cinco
minutos, o painel consulta esses arquivos pelo agente. A versão do Setup MNO é
mostrada separadamente da versão do Control Center. Se a validação falhar, o
catálogo embutido entra em contingência com aviso visual e evento de auditoria.

Depois de alterar o painel, o catálogo ou `VERSIONSETUP`:

```bash
./1_codigo_fonte/setupmno-control/generate-installers.sh
```

O comando recria mecanicamente os scripts `setupmno_control.sh` de x86 e ARM
com o mesmo bundle de fontes e gera os pacotes `.control-package/` de cada
arquitetura. Durante uma instalação ou atualização, os gatilhos validam esses
pacotes e promovem os arquivos para `.control/`.
