# Backup, restauração e rollback de dados

- Estado: `implemented`
- Atualizado em: 2026-08-23
- Público: mantenedor PRO MASTER e autores do futuro Help
- Ambientes: Debian, Ubuntu, WSL2 e Docker Swarm

## Resumo para leigos

Backup não é sinônimo de recuperação. Um arquivo pode existir, estar vazio,
incompleto, criptografado sem chave disponível ou depender de outra versão da
aplicação. O único backup confiável é aquele cujo processo de restauração foi
testado em ambiente isolado.

## Objetivo

Definir evidências mínimas antes de qualquer atualização ou ação stateful.

## Classifique o estado

| Tipo | Exemplos | Estratégia mínima |
|---|---|---|
| Configuração | stack YAML, regras e parâmetros | versionamento e diff |
| Segredo | senhas, chaves e tokens | cofre, rotação e acesso restrito |
| Banco | PostgreSQL, MySQL, Redis persistente | dump/snapshot consistente e restore |
| Arquivo | uploads e documentos | cópia consistente, integridade e restore |
| Swarm | estado de managers | backup coordenado do estado do Swarm |
| Imagem | digest do container | inventário e disponibilidade no registry |

Um rollback de imagem não desfaz uma migração de banco. Uma restauração de banco
não recria DNS, secrets ou regras do Traefik. O plano deve declarar cada camada.

## O que observar

- responsável pelo dado;
- horário e consistência do backup;
- retenção e local de armazenamento;
- criptografia e disponibilidade da chave;
- tamanho e hash do artefato;
- versão necessária para restaurar;
- RPO: quanto dado pode ser perdido;
- RTO: quanto tempo a recuperação pode levar;
- data, ambiente e resultado do último restore testado.

## Gate de mudança stateful

Uma mudança deve ser bloqueada quando:

- não há inventário dos dados afetados;
- o backup não é consistente com a aplicação;
- o restore nunca foi testado;
- a chave de recuperação não está disponível pelo processo autorizado;
- o rollback depende de apagar o único dado válido;
- não existe espaço ou janela para uma cópia segura.

## Restauração isolada

1. Crie ambiente temporário com nomes exclusivos.
2. Restaure sem conectar ao tráfego de produção.
3. Verifique integridade técnica e fluxo funcional mínimo.
4. Registre duração, versão e limitações.
5. Remova somente os recursos inventariados do teste.
6. Preserve evidências sanitizadas; nunca copie dados reais para documentação.

## Limites e segurança

- Não teste restore sobrescrevendo produção.
- Não coloque segredos no manifesto, logs ou argumentos de shell.
- Não confunda `docker service rollback` com rollback de dados.
- Não remova volumes como etapa de limpeza sem propriedade e nome literal
  confirmados.
- O futuro AI Safe Mode bloqueará ação stateful sem backup e restore
  comprováveis.

## Fontes oficiais

- [Docker Swarm backup and restore guidance](https://docs.docker.com/engine/swarm/admin_guide/)
- [Docker volumes backup, restore or migrate](https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes)
- [PostgreSQL backup and restore](https://www.postgresql.org/docs/current/backup.html)
- [MySQL backup and recovery](https://dev.mysql.com/doc/refman/8.4/en/backup-and-recovery.html)

## Publicação futura no Help

Apresentar um cartão por tipo de dado e uma pergunta central: “quando foi o
último restore aprovado?”. Evitar um selo verde baseado apenas na existência do
arquivo.
