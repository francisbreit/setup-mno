# Supply chain e SBOM runtime

- Versão inicial: Setup MNO v7.30.0
- Estado: implementado, aguardando homologação externa
- Escopo: AMD64 e ARM64, VPS e WSL2

## Problema resolvido

Antes desta etapa, o runtime possuía hashes do catálogo e dos pacotes internos,
mas não entregava uma visão única e verificável da origem dos scripts, das
referências de imagens e dos componentes empacotados. Isso dificultava detectar
drift, adulteração e dependências mutáveis.

## Artefatos por arquitetura

O gerador cria em `.control-package/supply-chain/`:

- `manifest.json`: identidade, contadores, tamanhos e hashes;
- `sbom.cdx.json`: SBOM CycloneDX 1.6;
- `image-inventory.json`: referências detectadas, scripts e expressões
  dinâmicas não resolvidas;
- `attestation.intoto.json`: in-toto Statement v1 com predicado SLSA Provenance
  v1.

O SHA-256 do manifesto e dos três documentos é gravado no `release.json`. O
instalador valida tudo antes de promover os arquivos atomicamente para
`/root/SetupLowCodeMno/.control/supply-chain/`.

## Fronteiras de confiança

- o painel web não recebe mount do host nem Docker socket;
- somente o agente lê o diretório runtime, montado como somente leitura;
- o agente valida arquivos regulares, ausência de symlink, inventário fixo,
  tamanho, JSON, versões, arquitetura e hashes;
- a interface recebe apenas contadores e estado, não caminhos ou conteúdo
  arbitrário;
- a feature não executa `pull`, deploy, atualização, DNS ou comandos Docker.

## O que a evidência significa

O SBOM tem composição declarada como `incomplete`: ele cobre os pacotes internos
e referências de containers encontradas pelos padrões do gerador, não todas as
bibliotecas existentes dentro de cada imagem. Referências por digest são
imutáveis; tags continuam mutáveis e aparecem como dívida técnica.

A atestação está marcada como `unsigned-sha256-bound`. Ela é ligada ao pacote
por SHA-256, mas ainda não possui envelope DSSE ou assinatura de uma identidade
independente. Portanto, esta versão não declara nível SLSA, autoria
criptograficamente autenticada nem transparência pública.

## Falha e rollback

Qualquer ausência, symlink, hash, tamanho, arquitetura ou contador divergente
interrompe a promoção antes de substituir o `release.json`. Para rollback,
reinstale o último pacote anterior validado; nenhum volume, stack ou dado de
aplicação precisa ser restaurado porque a feature altera apenas metadados
runtime somente leitura.

## Evolução prevista

1. resolver digests das imagens durante o build controlado;
2. impedir aumento não aprovado de tags mutáveis;
3. adicionar assinatura DSSE e identidade do construtor;
4. relacionar SBOM e selos à revalidação contínua e revogação por drift.
