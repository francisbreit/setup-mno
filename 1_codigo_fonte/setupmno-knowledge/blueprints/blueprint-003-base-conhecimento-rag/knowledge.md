---
{"schemaVersion":1,"documentId":"blueprint-003-base-conhecimento-rag-knowledge","documentVersion":"0.1.0","contentSHA256":"ac02f326d699d95e5c5b12daef5983a9bedf84c288cb5824b2d008ca7ada3b9e","documentType":"blueprint","blueprintId":"blueprint-003-base-conhecimento-rag","fictitious":true,"deployable":false,"title":"Blueprint 003 — Base de Conhecimento com IA e RAG (homologação)","setupVersion":"7.2.11","architectures":["amd64","arm64"],"category":"architecture","status":"reviewed","updatedAt":"2026-07-31","sourceType":"homologation-test","risk":"high","language":"pt-BR","tags":["blueprint","rag","inteligencia-artificial","qdrant","dify","ollama"],"sources":[{"sourceId":"blueprint-003-manifest","title":"Manifesto canônico fictício do Blueprint 003","sourceType":"setup-mno","location":"setupmno-knowledge/blueprints/blueprint-003-base-conhecimento-rag/blueprint.json","license":"maintainer-owned","verifiedAt":"2026-07-31"}],"homologation":{"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}}
---
# Blueprint 003 — Base de Conhecimento com IA e RAG

## Estado de homologação

Este documento é uma fixture fictícia para avaliar o Arquiteto de Blueprints. Ele não contém documentos privados, modelos aprovados nem uma implantação homologada.

## Objetivo

Simular uma base de conhecimento com ingestão controlada, recuperação rastreável e geração de respostas com fontes, usando Dify, Qdrant e inferência local opcional.

## Topologia

O Qdrant representa o armazenamento vetorial e seus metadados. O Dify representa os fluxos de ingestão, retrieval e resposta. Ollama com OpenWebUI representa a opção local de inferência e laboratório, condicionada à capacidade do servidor e à licença do modelo.

## Componentes

- QDRANT: vetores e metadados dos documentos aprovados.
- DIFY: aplicação de IA, ingestão, recuperação e política de resposta.
- OLLAMA + OPENWEBUI*: inferência local opcional e interface de laboratório.

## Pré-requisitos

A estimativa fictícia é de 16 GB de RAM mínima e 32 GB recomendada, em amd64 ou arm64. Modelo, contexto, simultaneidade, aceleração, volume documental, política de retenção e licenças precisam ser medidos e revisados.

## Ordem segura

1. Definir responsáveis, fontes permitidas e regras de retenção.
2. Preparar o Qdrant e uma coleção exclusiva de laboratório.
3. Preparar o Dify com limites de contexto e citações obrigatórias.
4. Avaliar o Ollama somente depois do gate de capacidade e licença.
5. Ingerir apenas documentos fictícios conhecidos e executar avaliações negativas.

## Validação

Uma pergunta conhecida deve recuperar a fonte correta e citá-la. Uma consulta fora do conjunto autorizado deve informar ausência de evidência. A interrupção do provedor deve produzir falha explícita ou contingência conhecida, nunca resposta inventada.

## Riscos e limites

Documentos podem conter instruções maliciosas, dados pessoais ou conteúdo sem licença. Similaridade vetorial não comprova verdade. A fixture não valida modelo, custo, desempenho, isolamento de tenant ou qualidade de uma base real.

## Rollback

Interromper novas ingestões, preservar o inventário documental, desativar a aplicação de laboratório e restaurar coleção e configuração compatíveis com a versão anterior.
