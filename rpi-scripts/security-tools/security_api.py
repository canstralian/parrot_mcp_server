#!/usr/bin/env python3
"""
Security Tools REST API
Provides RESTful endpoints for managing security scanning tools

⚠️  WARNING: FOR AUTHORIZED SECURITY TESTING ONLY
This API must ONLY be used for authorized security testing.
Unauthorized use is ILLEGAL.
"""

import os
import sys
import json
import subprocess
import hashlib
import time
from datetime import datetime
from pathlib import Path
from functools import wraps

from flask import Flask, request, jsonify, send_file
from werkzeug.exceptions import HTTPException

# Configuration
SCRIPT_DIR = Path(__file__).parent.absolute()
SECURITY_RESULTS_DIR = SCRIPT_DIR / "scan-results"
SECURITY_CONFIGS_DIR = SCRIPT_DIR / "configs"
SECURITY_AUDIT_LOG = SCRIPT_DIR.parent / "logs" / "security_audit.log"
API_KEY_FILE = SECURITY_CONFIGS_DIR / "api_keys.conf"

# Tool paths
NMAP_WRAPPER = SCRIPT_DIR / "nmap_wrapper.sh"
OPENVAS_WRAPPER = SCRIPT_DIR / "openvas_wrapper.sh"

# Create Flask app
app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 1 * 1024 * 1024  # 1MB max request size

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def audit_log(level, message, user="unknown", remote_addr="unknown"):
    """Write to security audit log"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    msgid = int(time.time() * 1000000)
    log_entry = f"[{timestamp}] [{level}] [msgid:{msgid}] [{user}@{remote_addr}] {message}\n"

    with open(SECURITY_AUDIT_LOG, 'a') as f:
        f.write(log_entry)


def validate_api_key(api_key, username):
    """Validate API key against stored hashes"""
    if not API_KEY_FILE.exists():
        audit_log("ERROR", f"API key file not found", username, request.remote_addr)
        return False

    # Hash the provided key
    key_hash = hashlib.sha256(api_key.encode()).hexdigest()

    # Check if hash exists for this user
    with open(API_KEY_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('#') or not line:
                continue

            if line == f"{username}:{key_hash}":
                return True

    audit_log("ERROR", f"Invalid API key for user: {username}", username, request.remote_addr)
    return False


def require_auth(f):
    """Decorator to require API key authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Get credentials from request
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            audit_log("ERROR", "Missing or invalid Authorization header", "unknown", request.remote_addr)
            return jsonify({"error": "Missing or invalid Authorization header"}), 401

        api_key = auth_header[7:]  # Remove 'Bearer ' prefix

        # Get username from request body or query params
        username = request.json.get('user') if request.json else request.args.get('user')
        if not username:
            audit_log("ERROR", "Missing username in request", "unknown", request.remote_addr)
            return jsonify({"error": "Missing username"}), 400

        # Validate API key
        if not validate_api_key(api_key, username):
            return jsonify({"error": "Authentication failed"}), 401

        # Store username in request context
        request.username = username

        return f(*args, **kwargs)

    return decorated_function


def run_tool(tool_path, args):
    """Execute security tool wrapper script"""
    cmd = [str(tool_path)] + args

    audit_log("INFO", f"Executing: {' '.join(cmd)}", request.username, request.remote_addr)

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )

        return {
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr
        }

    except subprocess.TimeoutExpired:
        audit_log("ERROR", f"Tool execution timeout: {tool_path}", request.username, request.remote_addr)
        return {
            "exit_code": 124,
            "stdout": "",
            "stderr": "Execution timeout"
        }
    except Exception as e:
        audit_log("ERROR", f"Tool execution failed: {str(e)}", request.username, request.remote_addr)
        return {
            "exit_code": 1,
            "stdout": "",
            "stderr": str(e)
        }


# =============================================================================
# API ENDPOINTS
# =============================================================================

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "service": "parrot-security-api",
        "version": "1.0.0",
        "timestamp": datetime.now().isoformat()
    })


@app.route('/api/v1/scan/nmap', methods=['POST'])
@require_auth
def nmap_scan():
    """
    Execute Nmap scan

    Request body:
    {
        "user": "username",
        "target": "192.168.1.100",
        "scan_type": "tcp",
        "ports": "80,443",
        "output": "custom_scan_name"
    }
    """
    data = request.json

    # Validate required fields
    if 'target' not in data:
        return jsonify({"error": "Missing required field: target"}), 400

    # Build command arguments
    args = [
        '-t', data['target'],
        '-u', request.username,
        '-k', request.headers.get('Authorization')[7:]  # Extract API key
    ]

    if 'scan_type' in data:
        args.extend(['-s', data['scan_type']])

    if 'ports' in data:
        args.extend(['-p', data['ports']])

    if 'output' in data:
        args.extend(['-o', data['output']])

    # Execute Nmap wrapper
    result = run_tool(NMAP_WRAPPER, args)

    if result['exit_code'] == 0:
        # Parse JSON output from wrapper
        try:
            scan_result = json.loads(result['stdout'])
            audit_log("INFO", f"Nmap scan completed: {scan_result.get('scan_id')}",
                     request.username, request.remote_addr)
            return jsonify(scan_result), 200
        except json.JSONDecodeError:
            return jsonify({
                "error": "Failed to parse scan result",
                "details": result['stdout']
            }), 500
    else:
        return jsonify({
            "error": "Scan failed",
            "exit_code": result['exit_code'],
            "stderr": result['stderr']
        }), 500


@app.route('/api/v1/scan/openvas', methods=['POST'])
@require_auth
def openvas_scan():
    """
    Execute OpenVAS scan

    Request body:
    {
        "user": "username",
        "target": "192.168.1.100",
        "config": "full_and_fast",
        "name": "Production Server Scan",
        "wait": false
    }
    """
    data = request.json

    # Validate required fields
    if 'target' not in data:
        return jsonify({"error": "Missing required field: target"}), 400

    # Build command arguments
    args = [
        '-t', data['target'],
        '-u', request.username,
        '-k', request.headers.get('Authorization')[7:]
    ]

    if 'config' in data:
        args.extend(['-c', data['config']])

    if 'name' in data:
        args.extend(['-n', data['name']])

    if 'output' in data:
        args.extend(['-o', data['output']])

    if data.get('wait', False):
        args.append('-w')

    # Execute OpenVAS wrapper
    result = run_tool(OPENVAS_WRAPPER, args)

    if result['exit_code'] == 0:
        # Parse JSON output from wrapper
        try:
            scan_result = json.loads(result['stdout'])
            audit_log("INFO", f"OpenVAS scan started: {scan_result.get('scan_id')}",
                     request.username, request.remote_addr)
            return jsonify(scan_result), 200
        except json.JSONDecodeError:
            return jsonify({
                "error": "Failed to parse scan result",
                "details": result['stdout']
            }), 500
    else:
        return jsonify({
            "error": "Scan failed",
            "exit_code": result['exit_code'],
            "stderr": result['stderr']
        }), 500


@app.route('/api/v1/results', methods=['GET'])
@require_auth
def list_results():
    """List available scan results"""
    try:
        results = []
        for result_file in SECURITY_RESULTS_DIR.iterdir():
            if result_file.is_file():
                results.append({
                    "filename": result_file.name,
                    "size": result_file.stat().st_size,
                    "modified": datetime.fromtimestamp(result_file.stat().st_mtime).isoformat()
                })

        return jsonify({"results": results}), 200

    except Exception as e:
        audit_log("ERROR", f"Failed to list results: {str(e)}", request.username, request.remote_addr)
        return jsonify({"error": str(e)}), 500


@app.route('/api/v1/results/<filename>', methods=['GET'])
@require_auth
def download_result(filename):
    """Download scan result file"""
    # Prevent directory traversal
    if '/' in filename or '\\' in filename or '..' in filename:
        audit_log("ERROR", f"Directory traversal attempt: {filename}", request.username, request.remote_addr)
        return jsonify({"error": "Invalid filename"}), 400

    file_path = SECURITY_RESULTS_DIR / filename

    if not file_path.exists():
        return jsonify({"error": "File not found"}), 404

    audit_log("INFO", f"Downloading result: {filename}", request.username, request.remote_addr)

    return send_file(file_path, as_attachment=True)


@app.route('/api/v1/config/whitelist', methods=['GET'])
@require_auth
def get_whitelist():
    """Get IP whitelist"""
    whitelist_file = SECURITY_CONFIGS_DIR / "ip_whitelist.conf"

    if not whitelist_file.exists():
        return jsonify({"whitelist": []}), 200

    with open(whitelist_file, 'r') as f:
        whitelist = [line.strip() for line in f if line.strip() and not line.startswith('#')]

    return jsonify({"whitelist": whitelist}), 200


@app.route('/api/v1/config/whitelist', methods=['POST'])
@require_auth
def update_whitelist():
    """Update IP whitelist"""
    data = request.json

    if 'whitelist' not in data or not isinstance(data['whitelist'], list):
        return jsonify({"error": "Invalid whitelist format"}), 400

    whitelist_file = SECURITY_CONFIGS_DIR / "ip_whitelist.conf"

    try:
        with open(whitelist_file, 'w') as f:
            f.write("# IP Whitelist (updated via API)\n")
            f.write(f"# Last update: {datetime.now().isoformat()}\n")
            f.write(f"# Updated by: {request.username}\n\n")
            for ip_range in data['whitelist']:
                f.write(f"{ip_range}\n")

        audit_log("INFO", f"Whitelist updated ({len(data['whitelist'])} entries)",
                 request.username, request.remote_addr)

        return jsonify({"message": "Whitelist updated successfully"}), 200

    except Exception as e:
        audit_log("ERROR", f"Failed to update whitelist: {str(e)}", request.username, request.remote_addr)
        return jsonify({"error": str(e)}), 500


# =============================================================================
# ERROR HANDLERS
# =============================================================================

@app.errorhandler(HTTPException)
def handle_http_exception(e):
    """Handle HTTP exceptions"""
    return jsonify({
        "error": e.name,
        "message": e.description,
        "status_code": e.code
    }), e.code


@app.errorhandler(Exception)
def handle_exception(e):
    """Handle uncaught exceptions"""
    audit_log("ERROR", f"Unhandled exception: {str(e)}", "system", "internal")
    return jsonify({
        "error": "Internal server error",
        "message": str(e)
    }), 500


# =============================================================================
# MAIN
# =============================================================================

if __name__ == '__main__':
    # Ensure directories exist
    SECURITY_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    SECURITY_CONFIGS_DIR.mkdir(parents=True, exist_ok=True)

    # Set restrictive permissions
    os.chmod(SECURITY_RESULTS_DIR, 0o700)
    os.chmod(SECURITY_CONFIGS_DIR, 0o700)

    # Run server
    app.run(
        host='127.0.0.1',  # Localhost only by default
        port=5000,
        debug=False  # Never use debug in production
    )
