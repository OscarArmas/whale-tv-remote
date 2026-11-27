#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -parse-as-library WhaleRemote/{RemoteViewModel,RemoteKeys,DlnaRemote,SsdpClient,UpnpHttp}.swift Tests/RemoteTests.swift -o "$out/RemoteTests"
"$out/RemoteTests"
