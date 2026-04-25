#!/bin/sh
# Smoke test for Fragile HTTP server

set -e

PORT=8080
PASS=0
FAIL=0

# Build
zig build -Doptimize=ReleaseFast

# Start server
./zig-out/bin/fragile & PID=$!
sleep 0.3

cleanup() {
    kill $PID 2>/dev/null || true
}
trap cleanup EXIT

check() {
    name=$1
    expected=$2
    actual=$3

    if [ "$actual" = "$expected" ]; then
        echo "  [PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

# Helper: extract status code from raw response
status() {
    printf "$1" | nc -w1 127.0.0.1 $PORT 2>/dev/null | head -1 | sed -n 's/.*HTTP\/[0-9.]* \([0-9]*\).*/\1/p'
}

echo "=== Implemented Methods ==="

check "GET" "200" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/)"
check "HEAD" "200" "$(curl -s -o /dev/null -w '%{http_code}' -I http://127.0.0.1:$PORT/)"

echo ""
echo "=== Unimplemented Methods (405) ==="

check "POST" "405" "$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:$PORT/)"
check "PUT" "405" "$(curl -s -o /dev/null -w '%{http_code}' -X PUT http://127.0.0.1:$PORT/)"
check "DELETE" "405" "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE http://127.0.0.1:$PORT/)"
check "OPTIONS" "405" "$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS http://127.0.0.1:$PORT/)"
check "CONNECT" "405" "$(status 'CONNECT / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n')"
check "TRACE" "405" "$(status 'TRACE / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n')"

echo ""
echo "=== Invalid Methods ==="

check "lowercase method" "400" "$(status 'get / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n')"
check "unknown method" "400" "$(status 'INVALID / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n')"

echo ""
echo "=== Protocol ==="

check "HTTP/1.0 rejected" "400" "$(status 'GET / HTTP/1.0\r\nHost: x\r\nConnection: close\r\n\r\n')"
check "HTTP/2 rejected" "400" "$(status 'GET / HTTP/2\r\nHost: x\r\nConnection: close\r\n\r\n')"

echo ""
echo "=== Host Header ==="

check "missing Host" "400" "$(status 'GET / HTTP/1.1\r\nConnection: close\r\n\r\n')"
check "duplicate Host" "400" "$(status 'GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\nConnection: close\r\n\r\n')"

echo ""
echo "=== Content-Length ==="

check "valid Content-Length" "405" "$(status 'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nConnection: close\r\n\r\ntest')"
check "duplicate Content-Length" "400" "$(status 'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')"
check "invalid Content-Length" "400" "$(status 'POST / HTTP/1.1\r\nHost: x\r\nContent-Length: abc\r\nConnection: close\r\n\r\n')"

echo ""
echo "=== Transfer-Encoding ==="

check "chunked rejected" "400" "$(status 'POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n')"

echo ""
echo "=== Line Folding ==="

check "SP folding rejected" "400" "$(status 'GET / HTTP/1.1\r\nHost: x\r\nX-Test: a\r\nConnection: close\r\n continued\r\n\r\n')"
check "HTAB folding rejected" "400" "$(status 'GET / HTTP/1.1\r\nHost: x\r\nX-Test: a\r\nConnection: close\r\n\tcontinued\r\n\r\n')"

echo ""
echo "=== Request Line ==="

check "double SP after method" "400" "$(status 'GET  / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n')"
check "double SP before proto" "400" "$(status 'GET /  HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n')"

echo ""
echo "=== Response Body ==="

check "body contains html" "1" "$(curl -s http://127.0.0.1:$PORT/ | grep -c '<!doctype html>')"

echo ""
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
