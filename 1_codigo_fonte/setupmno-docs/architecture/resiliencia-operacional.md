# Resiliência Operacional: Backup, Restauração, Atualização e Rollback

- Versão arquitetural: `1.0.0`
- Estado: `implemented`
- Maturidade da funcionalidade: `BETA`
- Escopo de planos: todos os planos possuem visualização consultiva; auditoria avançada restrita a PRO e PRO MASTER
- Ambientes: WSL2 AMD64, VPS Debian/Ubuntu AMD64 e ARM64

## Para iniciantes

No Setup MNO, cada aplicação instalada guarda dados de maneiras diferentes. Umas guardam apenas arquivos temporários na memória (*stateless*), outras guardam tudo no banco de dados PostgreSQL, outras usam volumes do Docker e algumas combinam banco com armazenamento de arquivos S3/MinIO (*híbridas*).

A **Resiliência Operacional** é a capacidade do sistema de continuar funcionando ou se recuperar rapidamente de acidentes, avaliando 4 pilares:
1. **Backup:** existe procedimento conhecido e configurado de cópia?
2. **Restauração (Restore):** a capacidade de restaurar os dados foi comprovada e testada?
3. **Atualização (Update):** a atualização de versão valida previamente a integridade do banco?
4. **Rollback:** em caso de falha, há um método seguro para voltar sem corromper os dados?

O painel do Control Center passa a exibir o diagnóstico claro de resiliência para cada ferramenta, apontando o nível de risco e as recomendações práticas para manter o ambiente seguro.

## Modelo mental

- **Backup** é o pneu estepe no porta-malas.
- **Restauração** é checar periodicamente se o estepe tem ar e se a chave de roda funciona.
- **Atualização** é fazer uma ultrapassagem na estrada após conferir a sinalização e o retrovisor.
- **Rollback** é a capacidade de frear e voltar para a faixa segura se a pista estiver bloqueada.

## Classificação de Persistência

Cada setup é classificado deterministamente em uma de 4 categorias:

| Categoria | Descrição | Exemplos | Nível de Risco | Requisito de Rollback |
| :--- | :--- | :--- | :--- | :--- |
| **Stateless** | Não retém dados persistentes essenciais no host; configs são efêmeras ou baseadas em variáveis de ambiente. | `changedetection`, `it-tools`, `excalidraw`, `dozzle` | Baixo | Reversão simples da tag da imagem Docker |
| **Database-Backed** | Depende primariamente de bancos relacionais ou vetoriais (`postgres_db`, `redis`, `clickhouse`). | `metabase`, `baserow`, `planka`, `actual-budget` | Médio | Dump SQL / backup transacional consistente antes do update |
| **Volume-Backed** | Armazena uploads, configurações em disco ou dados em Docker Named Volumes locais. | `filebrowser`, `adguardhome`, `duplicati`, `vaultwarden` | Médio-Alto | Cópia/Snapshot consistente do volume local |
| **Hybrid** | Combina banco relacional/vetorial + storage de objetos (MinIO/S3) ou múltiplos volumes interdependentes. | `chatwoot`, `typebot`, `evolution-api`, `n8n`, `dify`, `langfuse` | Crítico | Backup coordenado entre dump do banco e mídias do storage |

## Os 4 Pilares de Resiliência Mensurável

1. **Backup Readiness (Capacidade de Cópia):**
   - O Setup MNO mapeia o tipo de persistência e a localização exata dos volumes ou bancos;
   - Fornece runbooks de auditoria de dumps e snapshots sem expor credenciais.
2. **Restore Verifiability (Verificabilidade de Restauração):**
   - A existência de um arquivo de backup não garante recuperabilidade;
   - O sistema audita se existe teste documentado ou homologado de restauração.
3. **Update Safety (Segurança de Atualização):**
   - Atualizações de imagem não podem ser executadas automaticamente sem confirmação humana;
   - Verificação prévia de compatibilidade de arquitetura (x86 vs ARM64) e dependências.
4. **Rollback Strategy (Estratégia de Rollback):**
   - Diferenciação obrigatória entre rollback de imagem (stateless) e restauração de dados (stateful);
   - Bloqueio de rollback ingênuo de imagem sobre bancos que já executaram migrações destrutivas.

## Fronteiras de Segurança (AI Safe Mode)

- O agente e o painel continuam estritamente somente leitura (`/runtime-control:ro`);
- Nenhuma operação de backup, restauração, update ou rollback é disparada automaticamente em segundo plano;
- Diagnósticos e checklists são consultivos e fail-closed;
- Runbooks fornecem o passo a passo seguro para o operador executar no Terminal Seguro.
