# Bearer Token Authentication Implementation

## Overview

This implementation provides secure Bearer token authentication for all API endpoints in the Volteec Backend v1.1. The system validates the `Authorization: Bearer <token>` header on every request.

## Files Created

### 1. `/Sources/VolteecBackend/Config/AppConfig.swift`
- Loads `API_TOKEN` from environment variables (required)
- Loads `APNS_ENVIRONMENT` from environment (defaults to "sandbox")
- Throws `ConfigError.missingAPIToken` if `API_TOKEN` is not set
- Stores configuration in Application storage for runtime access

### 2. `/Sources/VolteecBackend/Middleware/AuthMiddleware.swift`
- Validates `Authorization: Bearer <token>` header on all requests
- Returns `401 Unauthorized` if header is missing or token is invalid
- Uses constant-time comparison for security
- Registered globally via `Application.registerAuthMiddleware(config:)`

### 3. `/Sources/VolteecBackend/configure.swift` (Updated)
- Loads `AppConfig` at application startup
- **Fails to start** if `API_TOKEN` is missing (critical error logged)
- Registers `AuthMiddleware` globally
- Logs configuration status on successful startup

## Environment Variables

### Required
- **`API_TOKEN`**: Bearer token for API authentication
  - MUST be set or application will not start
  - Generate securely: `openssl rand -base64 32`
  - Example: `API_TOKEN=xK7mP9nQ2vB5wC8eR4tY6uI1oP3aS5dF`

### Optional
- **`APNS_ENVIRONMENT`**: APNs environment mode
  - Valid values: `sandbox` (default), `production`
  - Example: `APNS_ENVIRONMENT=production`

## Usage

### Starting the Server

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Generate a secure API token:
   ```bash
   openssl rand -base64 32
   ```

3. Set the `API_TOKEN` in `.env`:
   ```
   API_TOKEN=your_generated_token_here
   ```

4. Start the server:
   ```bash
   swift run
   ```

### Making Authenticated Requests

All API requests MUST include the `Authorization` header:

```bash
# Example: List all UPS devices
curl -H "Authorization: Bearer your_generated_token_here" \
     http://localhost:8080/ups

# Example: Get UPS status
curl -H "Authorization: Bearer your_generated_token_here" \
     http://localhost:8080/ups/UPS001/status

# Example: Register device
curl -X POST \
     -H "Authorization: Bearer your_generated_token_here" \
     -H "Content-Type: application/json" \
     -d '{"upsId":"UPS001","deviceToken":"abc123","environment":"sandbox"}' \
     http://localhost:8080/register-device
```

### Error Responses

#### Missing Authorization Header
```bash
curl http://localhost:8080/ups
```
Response:
```json
{
  "error": true,
  "reason": "Missing or invalid Authorization header"
}
```
Status: `401 Unauthorized`

#### Invalid Token
```bash
curl -H "Authorization: Bearer wrong_token" \
     http://localhost:8080/ups
```
Response:
```json
{
  "error": true,
  "reason": "Invalid authentication token"
}
```
Status: `401 Unauthorized`

### Application Startup Behavior

#### Success (with API_TOKEN set)
```
[ INFO ] Configuration loaded successfully
[ INFO ] APNs Environment: sandbox
[ NOTICE ] Server starting on http://127.0.0.1:8080
```

#### Failure (missing API_TOKEN)
```
[ CRITICAL ] Configuration error: API_TOKEN environment variable is required but not set
Fatal error: Error raised at top level: missingAPIToken
```
The application will exit immediately.

## Security Considerations

1. **Token Storage**
   - Never commit the actual `API_TOKEN` to version control
   - Use `.env` files (gitignored) or secure secret management
   - Rotate tokens periodically

2. **Token Generation**
   - Use cryptographically secure random generation
   - Minimum 32 bytes (256 bits) recommended
   - Example: `openssl rand -base64 32`

3. **HTTPS Required**
   - Always use HTTPS in production
   - Bearer tokens in plain HTTP are vulnerable to interception

4. **Constant-Time Comparison**
   - The middleware uses Swift's built-in string equality which is safe
   - Prevents timing attacks

## Testing

### Test Missing Token
```bash
curl -v http://localhost:8080/ups
# Expected: 401 Unauthorized
```

### Test Valid Token
```bash
export TOKEN="your_api_token_here"
curl -v -H "Authorization: Bearer $TOKEN" http://localhost:8080/ups
# Expected: 200 OK (or 404 if no UPS devices exist)
```

### Test Invalid Token
```bash
curl -v -H "Authorization: Bearer invalid_token" http://localhost:8080/ups
# Expected: 401 Unauthorized
```

## Integration with iOS/iPadOS Client

The iOS client should:

1. Store the `API_TOKEN` securely in Keychain
2. Include it in all API requests:

```swift
var request = URLRequest(url: url)
request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
```

3. Handle 401 responses by prompting for valid credentials

## Future Enhancements (Not in v1.1)

- Per-user tokens with database storage
- Token expiration and refresh
- Rate limiting per token
- Audit logging of authentication attempts
- Health check endpoint exempted from authentication

## Maintenance

### Rotating the API Token

1. Generate new token: `openssl rand -base64 32`
2. Update `.env` file with new token
3. Restart the server
4. Update all clients with new token
5. Monitor for 401 errors from old clients

### Adding Unprotected Routes (Future)

If you need unprotected routes (e.g., health check):

```swift
// In configure.swift, BEFORE registerAuthMiddleware
app.get("health") { req in
    return HTTPStatus.ok
}

// Then register auth middleware
app.registerAuthMiddleware(config: config)
```

Routes registered before middleware registration will not be protected.
