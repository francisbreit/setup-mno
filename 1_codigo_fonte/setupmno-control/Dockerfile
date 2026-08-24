# syntax=docker/dockerfile:1.7
FROM --platform=$BUILDPLATFORM golang:1.25-alpine@sha256:56961d79ea8129efddcc0b8643fd8a5416b4e6228cfd477e3fd61deb2672c587 AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod main.go access.go knowledge.go retrieval.go routing.go prompts.go sre_snapshot.go blueprint_recommendation.go evals.go provider_evals.go feedback.go audit.go homologation.go ./
COPY web ./web
COPY catalog.json ./
COPY knowledge-package ./knowledge-package
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/setupmno-control .
RUN mkdir -p /out/feedback /out/audit \
    && touch /out/feedback/.keep /out/audit/.keep \
    && chown -R 65532:65532 /out/feedback /out/audit

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /out/setupmno-control /setupmno-control
COPY --from=builder /src/knowledge-package /knowledge-package
COPY --from=builder --chown=65532:65532 /out/feedback /feedback
COPY --from=builder --chown=65532:65532 /out/audit /audit
EXPOSE 8080 9090
ENTRYPOINT ["/setupmno-control"]
