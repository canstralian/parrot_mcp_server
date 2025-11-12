## API Documentation - Parrot MCP Server

Comprehensive REST API documentation for the enterprise Nmap integration.

## Base URL

```
http://localhost:8000/api/v1
```

For production, use HTTPS:
```
https://your-domain.com/api/v1
```

## Authentication

The API supports two authentication methods:

### 1. JWT Bearer Token

```http
Authorization: Bearer <access_token>
```

### 2. API Key

```http
X-API-Key: <your_api_key>
```

## Quick Start

### 1. Register a User

```bash
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "analyst",
    "email": "analyst@example.com",
    "password": "SecurePassword123!",
    "role": "analyst"
  }'
```

### 2. Login

```bash
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "analyst",
    "password": "SecurePassword123!"
  }'
```

Response:
```json
{
  "message": "Login successful",
  "user": {
    "id": 1,
    "username": "analyst",
    "role": "analyst"
  },
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "refresh_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "expires_in": 3600
}
```

### 3. Create a Scan

```bash
curl -X POST http://localhost:8000/api/v1/scans \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "target": "192.168.1.0/24",
    "scan_type": "quick",
    "priority": 5
  }'
```

---

## API Endpoints

### Authentication

#### POST /auth/register

Register a new user account.

**Request Body:**
```json
{
  "username": "string (required, 3-80 chars)",
  "email": "string (required, valid email)",
  "password": "string (required, min 8 chars)",
  "role": "string (optional, default: user)"
}
```

**Roles:**
- `user` - Basic user, can create and view own scans
- `analyst` - Can view all scans, create reports
- `admin` - Full system access

**Response:** `201 Created`
```json
{
  "message": "User created successfully",
  "user": {
    "id": 1,
    "username": "analyst",
    "email": "analyst@example.com",
    "role": "analyst",
    "is_active": true,
    "created_at": "2025-11-11T10:00:00Z"
  }
}
```

**Rate Limit:** 5 per hour

---

#### POST /auth/login

Authenticate and receive JWT tokens.

**Request Body:**
```json
{
  "username": "string (required)",
  "password": "string (required)"
}
```

**Response:** `200 OK`
```json
{
  "message": "Login successful",
  "user": { ... },
  "access_token": "eyJ0eXAi...",
  "refresh_token": "eyJ0eXAi...",
  "expires_in": 3600
}
```

**Rate Limit:** 10 per minute

---

#### POST /auth/api-key

Generate an API key for programmatic access.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:** `200 OK`
```json
{
  "message": "API key generated successfully",
  "api_key": "vM2JxTpQ7yKwZn4RfHcLbN...",
  "warning": "Store this key securely. It will not be shown again."
}
```

---

### Scans

#### POST /scans

Create and queue a new Nmap scan.

**Headers:**
```
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Request Body:**
```json
{
  "target": "string (required, IP or CIDR)",
  "scan_type": "string (required)",
  "custom_args": "string (optional, for custom scans)",
  "priority": "integer (optional, 1-10, default: 5)"
}
```

**Scan Types:**
- `quick` - Fast scan, top 100 ports
- `default` - Standard scan
- `full` - Full TCP scan, all ports
- `stealth` - Stealth SYN scan
- `os` - OS detection
- `vuln` - Vulnerability scan
- `custom` - Custom args (requires custom_args)

**Example:**
```json
{
  "target": "192.168.1.100",
  "scan_type": "full",
  "priority": 8
}
```

**Response:** `202 Accepted`
```json
{
  "message": "Scan queued successfully",
  "scan": {
    "id": 42,
    "task_id": "abc123-def456-...",
    "target": "192.168.1.100",
    "scan_type": "full",
    "status": "queued",
    "priority": 8,
    "created_at": "2025-11-11T10:30:00Z"
  },
  "task_id": "abc123-def456-..."
}
```

**Rate Limit:** 20 per hour

---

#### GET /scans

List scans with pagination and filters.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Query Parameters:**
- `page` (integer, default: 1) - Page number
- `per_page` (integer, default: 20, max: 100) - Items per page
- `status` (string, optional) - Filter by status
- `scan_type` (string, optional) - Filter by scan type

**Example:**
```bash
GET /scans?page=1&per_page=20&status=completed&scan_type=full
```

**Response:** `200 OK`
```json
{
  "scans": [
    {
      "id": 42,
      "task_id": "abc123-def456-...",
      "target": "192.168.1.100",
      "scan_type": "full",
      "status": "completed",
      "started_at": "2025-11-11T10:30:05Z",
      "completed_at": "2025-11-11T10:35:42Z",
      "duration_seconds": 337.5,
      "hosts_up": 1,
      "ports_found": 23,
      "created_at": "2025-11-11T10:30:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 150,
    "pages": 8
  }
}
```

**Permissions:**
- `user` role: Can only see own scans
- `analyst` and `admin`: Can see all scans

---

#### GET /scans/{scan_id}

Get detailed scan results.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Query Parameters:**
- `include_results` (boolean, default: true) - Include full parsed results

**Response:** `200 OK`
```json
{
  "scan": {
    "id": 42,
    "task_id": "abc123-def456-...",
    "user_id": 1,
    "target": "192.168.1.100",
    "scan_type": "full",
    "status": "completed",
    "started_at": "2025-11-11T10:30:05Z",
    "completed_at": "2025-11-11T10:35:42Z",
    "duration_seconds": 337.5,
    "hosts_up": 1,
    "ports_found": 23,
    "raw_output": "Starting Nmap 7.94...",
    "parsed_results": {
      "scan_info": { ... },
      "hosts": [
        {
          "status": "up",
          "addresses": [{"addr": "192.168.1.100", "addrtype": "ipv4"}],
          "hostnames": [],
          "ports": [
            {
              "protocol": "tcp",
              "portid": 22,
              "state": "open",
              "service": {
                "name": "ssh",
                "product": "OpenSSH",
                "version": "8.9p1"
              }
            }
          ]
        }
      ],
      "stats": {
        "hosts_up": 1,
        "hosts_down": 0,
        "total_hosts": 1,
        "total_ports": 23
      }
    }
  }
}
```

---

#### DELETE /scans/{scan_id}

Delete a scan.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:** `200 OK`
```json
{
  "message": "Scan deleted successfully"
}
```

**Permissions:**
- Users can delete own scans
- Analysts and admins can delete any scan

---

#### POST /scans/{scan_id}/cancel

Cancel a queued or running scan.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:** `200 OK`
```json
{
  "message": "Scan cancelled successfully"
}
```

---

### Statistics

#### GET /stats

Get scan statistics.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:** `200 OK`
```json
{
  "total_scans": 150,
  "by_status": {
    "completed": 120,
    "failed": 10,
    "queued": 15,
    "running": 5
  },
  "total_hosts_scanned": 1250,
  "total_ports_found": 15420
}
```

**Permissions:**
- `user`: Statistics for own scans only
- `analyst` and `admin`: All scans

---

### Administration

#### GET /admin/users

List all users (admin only).

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:** `200 OK`
```json
{
  "users": [
    {
      "id": 1,
      "username": "admin",
      "email": "admin@example.com",
      "role": "admin",
      "is_active": true,
      "created_at": "2025-11-10T00:00:00Z",
      "last_login": "2025-11-11T10:00:00Z"
    }
  ]
}
```

**Required Role:** `admin`

---

#### GET /admin/audit-logs

View audit logs (admin only).

**Headers:**
```
Authorization: Bearer <access_token>
```

**Query Parameters:**
- `page` (integer, default: 1)
- `per_page` (integer, default: 50, max: 100)

**Response:** `200 OK`
```json
{
  "logs": [
    {
      "id": 1234,
      "user_id": 1,
      "action": "POST /api/v1/scans",
      "resource_type": "scan",
      "resource_id": 42,
      "ip_address": "192.168.1.50",
      "user_agent": "curl/7.68.0",
      "status_code": 202,
      "details": {"path": "/api/v1/scans", "method": "POST"},
      "timestamp": "2025-11-11T10:30:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total": 5000,
    "pages": 100
  }
}
```

**Required Permission:** `system:audit`

---

## Error Responses

### Standard Error Format

```json
{
  "error": "Error name",
  "message": "Detailed error message",
  "status_code": 400
}
```

### Common Status Codes

- `200 OK` - Successful request
- `201 Created` - Resource created successfully
- `202 Accepted` - Request accepted for async processing
- `400 Bad Request` - Invalid request parameters
- `401 Unauthorized` - Missing or invalid authentication
- `403 Forbidden` - Insufficient permissions
- `404 Not Found` - Resource not found
- `429 Too Many Requests` - Rate limit exceeded
- `500 Internal Server Error` - Server error

### Example Error Response

```json
{
  "error": "Validation Error",
  "message": "Invalid target. Provide a valid IP or CIDR range.",
  "status_code": 400
}
```

---

## Rate Limiting

Rate limits are enforced per IP address and returned in response headers:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1699707600
```

When rate limit is exceeded:

```json
{
  "error": "Rate limit exceeded",
  "message": "100 per hour rate limit exceeded",
  "status_code": 429
}
```

---

## Code Examples

### Python

```python
import requests

BASE_URL = "http://localhost:8000/api/v1"

# Login
response = requests.post(f"{BASE_URL}/auth/login", json={
    "username": "analyst",
    "password": "SecurePassword123!"
})
tokens = response.json()
access_token = tokens["access_token"]

# Create scan
headers = {"Authorization": f"Bearer {access_token}"}
scan_response = requests.post(
    f"{BASE_URL}/scans",
    headers=headers,
    json={
        "target": "192.168.1.0/24",
        "scan_type": "quick"
    }
)
scan = scan_response.json()
scan_id = scan["scan"]["id"]

# Get scan results
result = requests.get(
    f"{BASE_URL}/scans/{scan_id}",
    headers=headers
)
print(result.json())
```

### JavaScript (Node.js)

```javascript
const axios = require('axios');

const BASE_URL = 'http://localhost:8000/api/v1';

// Login
const login = async () => {
  const response = await axios.post(`${BASE_URL}/auth/login`, {
    username: 'analyst',
    password: 'SecurePassword123!'
  });
  return response.data.access_token;
};

// Create scan
const createScan = async (token) => {
  const response = await axios.post(
    `${BASE_URL}/scans`,
    {
      target: '192.168.1.0/24',
      scan_type: 'quick'
    },
    {
      headers: { Authorization: `Bearer ${token}` }
    }
  );
  return response.data.scan.id;
};

// Main
(async () => {
  const token = await login();
  const scanId = await createScan(token);
  console.log(`Scan created: ${scanId}`);
})();
```

### cURL

```bash
# Store token
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"analyst","password":"SecurePassword123!"}' \
  | jq -r '.access_token')

# Create scan
curl -X POST http://localhost:8000/api/v1/scans \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "target": "192.168.1.0/24",
    "scan_type": "quick"
  }'
```

---

## Webhooks (Future Feature)

Coming soon: Configure webhooks to receive notifications when scans complete.

---

## API Versioning

The API follows semantic versioning. The current version is `v1`.

Breaking changes will be introduced in new versions (e.g., `v2`), with the previous version maintained for a deprecation period.

---

## Support

- GitHub Issues: https://github.com/canstralian/parrot_mcp_server/issues
- Security: See SECURITY.md

---

**Last Updated**: 2025-11-11
**API Version**: v1
