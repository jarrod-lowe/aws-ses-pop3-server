#!/bin/bash -eux
uname -a
dirname="$(dirname "$0")"
cd "${dirname}"
python3 -m pip install -r ../tls-key-layer-requirements.txt -t python
