#!/bin/bash

# Test script for Bearer token authentication
# Usage: ./test-auth.sh [base_url] [api_token]

BASE_URL="${1:-http://localhost:8080}"
API_TOKEN="${2:-test_token_123}"

echo "Testing Volteec Backend Authentication"
echo "======================================="
echo "Base URL: $BASE_URL"
echo ""

# Test 1: Missing Authorization header
echo "Test 1: Request without Authorization header"
echo "Expected: 401 Unauthorized"
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" "$BASE_URL/ups")
HTTP_STATUS=$(echo "$RESPONSE" | grep HTTP_STATUS | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')
echo "Status: $HTTP_STATUS"
echo "Body: $BODY"
echo ""

# Test 2: Invalid token
echo "Test 2: Request with invalid token"
echo "Expected: 401 Unauthorized"
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer invalid_token" "$BASE_URL/ups")
HTTP_STATUS=$(echo "$RESPONSE" | grep HTTP_STATUS | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')
echo "Status: $HTTP_STATUS"
echo "Body: $BODY"
echo ""

# Test 3: Valid token
echo "Test 3: Request with valid token"
echo "Expected: 200 OK (or 404/empty array if no data)"
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $API_TOKEN" "$BASE_URL/ups")
HTTP_STATUS=$(echo "$RESPONSE" | grep HTTP_STATUS | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')
echo "Status: $HTTP_STATUS"
echo "Body: $BODY"
echo ""

# Test 4: Valid token with POST
echo "Test 4: POST request with valid token (register device)"
echo "Expected: 201 Created or 404 (UPS not found)"
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"upsId":"TEST_UPS","deviceToken":"test_device_123","environment":"sandbox"}' \
  "$BASE_URL/register-device")
HTTP_STATUS=$(echo "$RESPONSE" | grep HTTP_STATUS | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')
echo "Status: $HTTP_STATUS"
echo "Body: $BODY"
echo ""

echo "======================================="
echo "Test complete!"
