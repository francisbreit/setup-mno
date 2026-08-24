#!/usr/bin/env bash
set -Eeuo pipefail

# Arquivo de teste negativo. O gate deve bloquear sem executar.
sudo docker -H unix:///var/run/docker.sock service ls
