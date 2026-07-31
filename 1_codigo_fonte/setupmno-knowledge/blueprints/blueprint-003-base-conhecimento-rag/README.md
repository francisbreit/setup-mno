# Base de Conhecimento com IA e RAG

> EXEMPLO FICTÍCIO. Não contém dataset real, modelo aprovado ou evidência de homologação.

## Objetivo

Demonstrar uma arquitetura de recuperação documental com rastreabilidade, política de acesso e inferência local opcional.

## Arquitetura

O Qdrant representa o índice vetorial. O Dify representa ingestão, recuperação e aplicação. Ollama e OpenWebUI representam a alternativa local condicionada à capacidade do servidor.

## Componentes

| Ordem | Setup | Responsabilidade |
|---|---|---|
| 1 | QDRANT | Vetores e metadados |
| 2 | DIFY | Aplicação e política RAG |
| 3 | OLLAMA + OPENWEBUI* | Inferência local opcional no projeto real |

## Pré-requisitos

- Inventário documental e responsáveis.
- Política de retenção e acesso.
- Modelo e licença aprovados.
- Avaliação real de memória, CPU e aceleração.

## Ordem de instalação

Defina a política documental antes de criar coleções. Configure a aplicação e só depois selecione o modelo local compatível.

## Validação

Use perguntas com resposta conhecida, perguntas sem fonte e tentativas de atravessar limites documentais. Meça citações corretas, recusas e latência.

## Riscos e limites

Documentos podem conter instruções maliciosas. Modelos podem alucinar e a estimativa de recursos é apenas fictícia. Nenhum conteúdo privado deve entrar sem governança.

## Rollback

Interrompa ingestões, preserve o inventário, restaure coleção e aplicação da mesma versão e repita o conjunto de avaliações.

## Vídeos e links

- [Vídeo fictício sobre RAG seguro](https://videos.setupmno.invalid/blueprints/003/rag-seguro)
- [Matriz fictícia de evidências](https://docs.setupmno.invalid/blueprints/003/evidencias)

## Promoção para produção

Exige dataset aprovado, política de acesso, evals, limites medidos e procedimento testado de backup e restauração.
