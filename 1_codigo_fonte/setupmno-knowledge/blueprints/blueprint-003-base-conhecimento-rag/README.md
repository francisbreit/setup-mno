# Base de Conhecimento com IA e RAG

> GUIA BETA. Pode ser seguido manualmente, mas ainda não foi homologado de ponta a ponta. Valide modelo, dados e capacidade antes de avançar.

## Objetivo

Orientar a montagem de uma arquitetura de recuperação documental com rastreabilidade, política de acesso e inferência local opcional.

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

Defina a política documental antes de criar coleções. Instale Qdrant, crie a coleção, instale Dify e sua conta administrativa, cadastre o provedor sem expor chaves e só depois selecione e conecte o modelo local compatível. Importe primeiro um conjunto documental controlado.

## Validação

Use perguntas com resposta conhecida, perguntas sem fonte e tentativas de atravessar limites documentais. Meça citações corretas, recusas e latência.

## Riscos e limites

Documentos podem conter instruções maliciosas. Modelos podem alucinar e a estimativa de recursos é preliminar. Nenhum conteúdo privado deve entrar sem governança.

## Rollback

Interrompa ingestões, preserve o inventário, restaure coleção e aplicação da mesma versão e repita o conjunto de avaliações.

## Downloads, vídeos e PDFs

- O ZIP deste Blueprint está disponível no Control Center.
- Vídeo sobre RAG seguro: em preparação.
- PDF com matriz de evidências: em preparação.

## Homologação futura

Exige dataset aprovado, política de acesso, evals, limites medidos e procedimento testado de backup e restauração.
