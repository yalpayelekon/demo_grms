#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8082}"

echo "[grms-smoke] Checking: $BASE_URL/health"
curl -fsS "$BASE_URL/health" >/dev/null

echo "[grms-smoke] Checking: $BASE_URL/"
curl -fsS "$BASE_URL/" >/dev/null

echo "[grms-smoke] Checking: $BASE_URL/dashboard"
curl -fsS "$BASE_URL/dashboard" >/dev/null

echo "[grms-smoke] Checking: $BASE_URL/testcomm/rooms/Demo%20101"
curl -fsS "$BASE_URL/testcomm/rooms/Demo%20101" >/dev/null

echo "[grms-smoke] All checks returned HTTP 200."
