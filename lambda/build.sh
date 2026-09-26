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

# Drop files that embed the build machine's interpreter path, so the package is
# identical on a laptop and a CI runner: console scripts (bin/) have a shebang
# like #!/path/to/python3, and each dist-info RECORD lists those scripts' hashes.
# Lambda never runs these scripts; RECORD is only used by `pip uninstall`.
rm -rf build/bin build/*.dist-info/RECORD
