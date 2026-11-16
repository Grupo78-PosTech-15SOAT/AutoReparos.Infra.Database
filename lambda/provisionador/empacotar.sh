#!/usr/bin/env bash
# Gera lambda/provisionador/build/ (código + pg8000 puro Python), que o Terraform compacta
# com archive_file. Rode antes de `terraform plan`/`apply` no diretório terraform/.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
python3 -m pip install --quiet --no-compile --only-binary=:all: --target build -r requirements.txt
cp provisionador.py build/
