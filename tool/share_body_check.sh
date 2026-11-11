#!/usr/bin/env bash
# The iOS Share extension's request bodies, proved on the Mac with a plain
# swiftc build — no simulator, no Xcode project, no Pods (F-197).
#
# Compiles UploadViewModel.swift with the extension's own Foundation-only
# helpers (ShelfPick, PlaylistAnswer, ResumableUpload, UploadClient) and a
# stand-in for APIClient (the real one needs FirebaseAuth): the stand-in
# records each body and refuses, so nothing reaches the network. main.swift
# asserts what fn_create_upload_session and fn_create_multi_image_session are
# sent. Exit 0 = PASS.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
share="$here/../ios/Share"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
xcrun swiftc -swift-version 5 -o "$out/check" \
  "$share/UploadViewModel.swift" "$share/ShelfPick.swift" \
  "$share/PlaylistAnswer.swift" "$share/ResumableUpload.swift" \
  "$share/UploadClient.swift" \
  "$here/share_body_check/stubs.swift" "$here/share_body_check/main.swift"
"$out/check"
