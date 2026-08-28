# syntax=docker/dockerfile:1.7
ARG STRIX_SANDBOX_BASE
FROM ${STRIX_SANDBOX_BASE}

LABEL org.opencontainers.image.title="Setup MNO SRE-6 isolated executor" \
      org.opencontainers.image.version="1.1.0" \
      org.opencontainers.image.licenses="Apache-2.0" \
      io.setupmno.maturity="beta"

ARG STRIX_WHEEL_URL
ARG STRIX_WHEEL_SHA256

USER root
RUN test -n "$STRIX_WHEEL_URL" && test -n "$STRIX_WHEEL_SHA256" \
    && wheel_file="/tmp/${STRIX_WHEEL_URL##*/}" \
    && case "$wheel_file" in /tmp/strix_agent-1.5.3-*.whl) ;; *) exit 12 ;; esac \
    && curl -fsSL "$STRIX_WHEEL_URL" -o "$wheel_file" \
    && echo "$STRIX_WHEEL_SHA256  $wheel_file" | sha256sum -c - \
    && /app/.venv/bin/pip install --no-cache-dir "$wheel_file" \
    && rm -f "$wheel_file" \
    && rm -f /usr/bin/sudo /bin/su /usr/bin/su \
    && find /etc/sudoers.d -mindepth 1 -maxdepth 1 -type f -delete \
    && if command -v setcap >/dev/null 2>&1 && command -v nmap >/dev/null 2>&1; then setcap -r "$(command -v nmap)" || true; fi \
    && useradd --uid 61000 --user-group --create-home --shell /usr/sbin/nologin setupmno-strix \
    && install -d -o root -g root -m 0755 /input \
    && install -d -o 61000 -g 61000 -m 0700 /workspace

COPY --chown=root:root strix-lab/executor.py /opt/setupmno/strix-executor.py
COPY --chown=root:root strix-lab/validate.py /opt/setupmno/validate.py
RUN chmod 0555 /opt/setupmno/strix-executor.py /opt/setupmno/validate.py

ENV HOME=/tmp/home \
    STRIX_TELEMETRY=0 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
USER 61000:61000
WORKDIR /workspace
ENTRYPOINT ["/app/.venv/bin/python", "/opt/setupmno/strix-executor.py"]
