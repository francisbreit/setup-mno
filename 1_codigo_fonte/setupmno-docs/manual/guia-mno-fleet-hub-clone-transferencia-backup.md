# Manual Operacional: MNO Fleet Hub — Clone, Transferência e Backup Universal

- Estado: `implemented`
- Maturidade da funcionalidade: `beta`
- Versão do Setup MNO: `v7.48.1`
- Versão do Control Center: `v4.44.4`
- Ambientes Alvo: Torre Master (Cockpit Local no WSL2 ou VPS) e Nós Workers (VPS Remotas)
- Ambientes Homologados: WSL2 (Windows 10/11 x86_64), Ubuntu 22.04/24.04 (x86_64 e ARM64), Debian 12/13 (x86_64 e ARM64)
- Destinatário: Francis Breit (Francis MNO), alunos, agências e profissionais de DevOps

---

## 1. Para Iniciantes — O Que É e Qual Problema Foi Resolvido?

### O Problema
Antes do MNO Fleet Hub, quando um usuário precisava mudar seu sistema para um servidor mais potente ou fazer backup de segurança, o processo era um pesadelo:
1. Era preciso exportar arquivos do banco de dados na linha de comando arriscando corromper as tabelas se o banco estivesse gravando;
2. Copiar pastas pesadas de imagens e áudios de WhatsApp sem saber se todas as permissões seriam mantidas;
3. Se fosse um **Combo Integrado** (como Chatwoot conectado com Evolution API, RabbitMQ e MinIO), era comum esquecer uma ferramenta para trás ou quebrar o link das mídias;
4. No final, era preciso abrir portas no firewall da VPS e alterar manualmente os apontamentos de DNS para que a internet encontrasse o novo servidor.

### A Solução MNO
O **Fleet Clone Universal** transforma esse processo complexo em uma operação guiada e visual de **1 clique**. Agora, a partir de um menu intuitivo no terminal (`fleet-clone.sh`) ou pelo Control Center:
- O sistema faz **Raio-X** dos servidores antes de tocar em qualquer dado;
- Reconhece **Combos completos** automaticamente e pergunta se você quer levar todo mundo junto;
- Cria **Backups Portáteis (.tar.gz)** independentes de arquitetura para você guardar no seu computador ou restaurar em qualquer VPS;
- Trata o armazenamento de arquivos (MinIO S3) de forma isolada para **não quebrar links históricos de conversas e áudios**;
- Comuta o **DNS no Cloudflare Tunnel** na hora certa, sem expor portas na internet;
- Mantém os dados antigos no servidor de origem congelados com sufixo de segurança para que você tenha **100% de garantia de Rollback**.

### Modelo Mental: A "Cápsula do Tempo" e a "Mudança Inteligente"
- **Transferência ao Vivo (Opção 2):** É como uma transportadora profissional. Ela desmonta sua empresa digital no servidor A, monta no servidor B e vai no correio (Cloudflare) mudar o endereço de entrega das cartas. Tudo em menos de 1 minuto.
- **Backup Portátil (Opção 4):** É como criar uma **"Cápsula do Tempo"** compacta (`.tar.gz`). Ela guarda o código, as regras, os bancos de dados e as fotos.
- **Restauração Universal (Opção 5):** É como abrir essa cápsula em qualquer terreno novo. O Setup MNO constrói as fundações (bancos de dados, redes e volumes), restaura as informações e pergunta: *"Quer ligar o endereço na internet agora (Disaster Recovery) ou prefere manter como laboratório de testes (Clone)?"*.

---

## 2. Os 5 Modos de Operação Explicados

O utilitário oficial fica localizado em `/root/SetupLowCodeMno/fleet-clone.sh`. Ele oferece 5 opções principais:

### Opção 1: Raio-X da Frota (Hardware & Resource Preflight)
- **O que faz:** Examina a arquitetura do processador (`x86_64` vs `arm64`), quantidade de memória RAM total e livre, disco disponível e a lista de aplicações instaladas em cada servidor.
- **Por que importa:** Impede que você tente restaurar uma aplicação pesada em um servidor sem memória ou tente migrar containers diretamente entre tipos incompatíveis de processador.

### Opção 2: Transferir Aplicação para outro Servidor (Com migração de DNS Cloudflare)
- **Quando usar:** Quando você contratou uma VPS melhor ou quer esvaziar um servidor sobrecarregado.
- **Fluxo de execução:**
  1. Cria snapshot dos volumes de dados persistentes;
  2. Gera dump lógico atômico do banco de dados (PostgreSQL, MySQL 8.0/8.4 ou MongoDB);
  3. Transfere os pacotes compactados via canal SSH seguro;
  4. Restaura volumes e dados no servidor de destino;
  5. Sobe a stack no Docker Swarm do novo servidor;
  6. Comuta o registro CNAME no Cloudflare Tunnel para o destino;
  7. Desliga a stack antiga na origem para liberar RAM;
  8. Renomeia os volumes antigos na origem para `<volume>_frozen_pre_transfer_<datahora>` (segurança absoluta).

### Opção 3: Clonar Aplicação para Teste (Sem alterar DNS)
- **Quando usar:** Quando você quer testar uma atualização arriscada ou novo módulo em uma VPS de homologação.
- **Diferencial:** Realiza todo o processo da Opção 2, mas **NÃO altera o DNS da Cloudflare** e não desliga a aplicação na origem. Sua produção continua intacta na internet enquanto você testa a réplica.

### Opção 4: Criar Backup Portátil (.tar.gz compatível com qualquer arquitetura)
- **Quando usar:** Para guardar cópias de segurança semanais ou transferir sistemas entre processadores diferentes (ex: de Intel/AMD para Oracle ARM).
- **Detecção de Combos:** Se a aplicação selecionada fizer parte de um Combo (como Chatwoot + Evolution + MinIO + RabbitMQ), o assistente pergunta:
  - *Opção A:* **MIGRAR/SALVAR COMBO COMPLETO** (empacota todas as ferramentas irmãs juntas).
  - *Opção B:* **SALVAR APENAS A FERRAMENTA SELECIONADA** (salva apenas a stack isolada).
- **Onde é salvo:** O arquivo é gravado em `/root/backup_fleet/<app>_universal_backup_<datahora>.tar.gz`.

### Opção 5: Restaurar Backup Portátil em um Servidor (Local ou Remoto via SSH)
- **Quando usar:** Para subir uma cópia guardada em uma nova VPS ou após um desastre.
- **Fluxo de execução:**
  1. O usuário escolhe o arquivo `.tar.gz` (o sistema lista os backups salvos em `/root/backup_fleet/` ou aceita caminho manual);
  2. Escolhe o servidor de destino (o servidor local ou qualquer VPS pareada na frota);
  3. O Setup MNO confere memória RAM e espaço em disco;
  4. Provisiona dependências automáticas necessárias (Postgres, MySQL, MinIO, RabbitMQ);
  5. Descompacta os volumes persistentes com as permissões corretas;
  6. Restaura as tabelas e dados nos bancos;
  7. Faz deploy da stack no Docker Swarm;
  8. Pergunta se o usuário quer comutar o DNS (Disaster Recovery) ou manter o domínio inalterado (Clone).

---

## 3. Nota Técnica para DevOps — Arquitetura e Engenharia

### Topologia do Pacote Portátil Standalone (`.tar.gz`)
O backup gerado implementa o `manifest.json` com `schemaVersion: 2`:

```text
meu_app_universal_backup_20260914T150000Z.tar.gz
├── manifest.json                  # Metadados completos do backup
├── stacks/                        # Definições das stacks
│   ├── chatwootf0e026b.yaml
│   ├── evolution2f0e026b.yaml
│   └── rabbitmqf0e026b.yaml
├── volumes/                       # Snapshots atômicos de cada volume
│   ├── vol_chatwoot_data.tar.gz
│   └── vol_evolution_instances.tar.gz
└── dumps/                         # Dumps lógicos atômicos dos bancos
    ├── chatwoot_pg_dump.sql.gz
    └── mautic_mysql_dump.sql.gz
```

### Inteligência Heurística de Combos (`sufixo_app`)
Os scripts instaladores de combo do Setup MNO geram um sufixo aleatório de 7 caracteres hexadecimais (ex: `f0e026b`).
O motor do Fleet Clone extrai `${stack: -7}` e varre o Swarm buscando todas as stacks irmãs. Ao detectar mais de uma ocorrência, aciona o `detect_app_combo_context`, montando a lista atômica de migração `apps_to_migrate`.

### A Política de Isolamento Multi-MinIO
Diferente de painéis comuns que tentam mesclar buckets em uma instância compartilhada, o Setup MNO adota o **Isolamento de Instâncias no Swarm**:
- **O Problema dos Links Históricos:** Aplicações de chat gravam o endereço absoluto do MinIO no PostgreSQL (ex: `https://s3.cliente.com.br/bucket/...`). Mudar o MinIO para outro host causaria 100% de perda visual de fotos e áudios antigos.
- **A Solução:** Como a federação opera em Docker Swarm com Traefik e Cloudflare Tunnel, não há colisão de portas de host. O MinIO daquele combo é transferido como uma stack independente com seu próprio volume, e o DNS `s3.cliente.com.br` é comutado para o novo nó. Se o usuário optar por manter na origem, uma trava rígida proíbe a rotina pós-transferência de desligar ou pausar a stack do MinIO.

### Motores de Banco de Dados Suportados
1. **PostgreSQL:** Dump lógico atômico via `pg_dump -U postgres --clean --if-exists` comprimido em streaming gzip. Restauração idempotente checando existência prévia com `SELECT 1 FROM pg_database`.
2. **MySQL 8.4 (Percona):** Dump com `--single-transaction --quick --add-drop-table` com senha extraída dinamicamente de Docker secrets ou `.env`.
3. **MySQL 8.0:** Provisionamento via `ensure_mysql80_ready` isolado em rede interna para evitar colisões com stacks 8.4.
4. **MongoDB (NoSQL):** Dump consistente via `mongodump --archive --gzip` e restauração via `mongorestore --archive --gzip --drop` para ferramentas como RocketChat e LibreChat.
5. **Bancos Vetoriais (Qdrant / Milvus):** Snapshot de volume físico consistente com congelamento temporário de escrita.

### Governança e Notificações (MNO Sentinel)
Ao concluir qualquer transferência ou restauração com sucesso:
- **Telegram Bot:** Envia mensagem executiva com o nome da aplicação, servidores envolvidos, contagem de volumes restaurados, volumes congelados na origem e status da rota DNS.
- **Webhook n8n:** Emite payload estruturado com evento `fleet_migration_completed` para acionamento de fluxos adicionais (notificação de equipe no WhatsApp ou atualização de inventário).

---

## 4. Passo a Passo: Como Operar pelo Terminal

### Pré-requisitos
- Ter acesso root ao servidor;
- Ter o Setup MNO instalado (versão v7.48.0 ou superior);
- Se for migrar entre servidores remotos, ter os nós pareados no MNO Fleet Hub da Torre Master.

### Executando a Ferramenta
1. Conecte-se via SSH ou abra o Terminal Seguro no Control Center:
   ```bash
   /root/SetupLowCodeMno/fleet-clone.sh
   ```
2. No menu principal, escolha a ação desejada:
   - Digite `1` para ver o **Raio-X** de todos os servidores conectados;
   - Digite `2` para **Transferir com comutação de DNS**;
   - Digite `4` para **Criar Backup Portátil (.tar.gz)**;
   - Digite `5` para **Restaurar Backup Portátil**.
3. Siga as caixas interativas do Whiptail. Ao final, confira o resumo detalhado exibido na tela.

---

## 5. Cuidados, Limites e Segurança

1. **Hardware Parity Gate (Trava de Arquitetura):**
   - Servidores com mesma CPU (`x86_64` ⇄ `x86_64` ou `ARM64` ⇄ `ARM64`): Transferência ao vivo autorizada.
   - Servidores com CPUs diferentes (`x86_64` ⇄ `ARM64`): A transferência ao vivo de containers é bloqueada por segurança. Nesse caso, use a **Opção 4 (Backup Portátil)**, que salva os dados limpos e permite restaurar sem erros na outra arquitetura.
2. **Preflight de Recursos:**
   - O destino precisa ter RAM livre maior ou igual ao consumo declarado da aplicação;
   - O disco livre precisa ser de pelo menos **1.2x o tamanho dos volumes**.
3. **Rollback Imediato:**
   - Se por qualquer motivo a aplicação não subir no destino, a origem **NÃO é desligada**;
   - Se a transferência concluir mas você decidir voltar atrás, os volumes originais na máquina antiga continuam intactos no disco com o prefixo `_frozen_pre_transfer_`. Basta renomear o volume e reiniciar a stack.

---

## 6. Como Francis MNO Pode Explicar para a Comunidade

> *"Fala família MNO! Sabe qual é o maior medo de quem tem uma agência digital ou roda sistemas de clientes? É o servidor travar e você perder tudo, ou precisar trocar de VPS e passar 3 dias reconfigurando banco, áudios do WhatsApp e DNS na mão.*  
>  
> *No Setup MNO, nós criamos o **Fleet Clone Universal**. Ele é o único sistema do mercado que entende quando você tem um combo completo (Chatwoot, WhatsApp, RabbitMQ e MinIO) e faz o backup de todas as ferramentas juntas em 1 clique. E se você quiser mudar de servidor, ele move os dados e muda o apontamento no Cloudflare Tunnel automaticamente, com zero portas abertas no firewall! Seus dados seguros, seus áudios antigos funcionando 100% e sua empresa sempre protegida."*
