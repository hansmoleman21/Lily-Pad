#!/usr/bin/env bash
# Build the Lambda package into lambda/build/ (zipped by Terraform's archive_file).
# Installs Linux x86_64 wheels so compiled deps (cryptography) match the Lambda
# runtime. --no-compile keeps the output byte-identical across builds: .pyc files
# embed source mtimes, which would change the zip hash and redeploy the Lambda
# on every plan.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
cp handler.py phrases.py build/
python3 -m pip install \
  --platform manylinux2014_x86_64 \
  --python-version 3.12 \
  --only-binary=:all: \
  --no-compile \
  --quiet \
  --target build \
  -r requirements.txt
