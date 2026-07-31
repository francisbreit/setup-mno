# syntax=docker/dockerfile:1.7
FROM --platform=$BUILDPLATFORM golang:1.25-alpine@sha256:56961d79ea8129efddcc0b8643fd8a5416b4e6228cfd477e3fd61deb2672c587 AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod main.go knowledge.go retrieval.go ./
COPY web ./web
COPY catalog.json ./
COPY knowledge-package ./knowledge-package
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/setupmno-control .

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /out/setupmno-control /setupmno-control
COPY --from=builder /src/knowledge-package /knowledge-package
EXPOSE 8080 9090
ENTRYPOINT ["/setupmno-control"]
