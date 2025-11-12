#!/usr/bin/env python3
"""
log_stream_sse.py - Minimal SSE (Server-Sent Events) log streaming server

Usage:
    ./log_stream_sse.py [--log-file=<path>] [--port=<port>] [--host=<host>]

Description:
    Provides real-time log streaming via SSE protocol on /logs/stream endpoint.
    Uses only Python stdlib - no external dependencies required.
    Follows log file similar to 'tail -F' (handles log rotation).

Options:
    --log-file=<path>   Path to log file (default: ./logs/parrot.log)
    --port=<port>       Port to listen on (default: 8080)
    --host=<host>       Host to bind to (default: 0.0.0.0)
    --help              Show this help message

Endpoints:
    GET /logs/stream    SSE stream of log entries (tail -F style)
    GET /               Simple status page with instructions
    GET /health         Health check endpoint

Example:
    # Start server
    ./log_stream_sse.py --log-file=./logs/parrot.log --port=8080

    # Connect with curl
    curl -N http://localhost:8080/logs/stream

    # Connect with browser JavaScript
    const eventSource = new EventSource('http://localhost:8080/logs/stream');
    eventSource.onmessage = (event) => console.log(event.data);
"""

import os
import sys
import time
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread
from pathlib import Path


class LogFollower:
    """Follows a log file like 'tail -F', handling rotation."""
    
    def __init__(self, filepath):
        self.filepath = filepath
        self.file_handle = None
        self.inode = None
        self.open_file()
    
    def open_file(self):
        """Open the log file and seek to end."""
        try:
            if self.file_handle:
                self.file_handle.close()
            
            # Create directory if it doesn't exist
            os.makedirs(os.path.dirname(self.filepath), exist_ok=True)
            
            # Create file if it doesn't exist
            if not os.path.exists(self.filepath):
                Path(self.filepath).touch()
            
            self.file_handle = open(self.filepath, 'r')
            # Seek to end of file
            self.file_handle.seek(0, 2)
            stat = os.fstat(self.file_handle.fileno())
            self.inode = stat.st_ino
        except Exception as e:
            print(f"[ERROR] Failed to open log file {self.filepath}: {e}", file=sys.stderr)
            self.file_handle = None
            self.inode = None
    
    def check_rotation(self):
        """Check if log file has been rotated and reopen if needed."""
        try:
            current_inode = os.stat(self.filepath).st_ino
            if current_inode != self.inode:
                # File has been rotated
                self.open_file()
                return True
        except (OSError, IOError):
            # File doesn't exist (might be between rotation)
            time.sleep(0.1)
            try:
                self.open_file()
                return True
            except Exception:
                pass
        return False
    
    def read_new_lines(self):
        """Read new lines from log file."""
        if not self.file_handle:
            self.open_file()
            return []
        
        try:
            # Check for rotation
            self.check_rotation()
            
            # Read new lines
            lines = []
            while True:
                line = self.file_handle.readline()
                if not line:
                    break
                lines.append(line.rstrip('\n\r'))
            
            return lines
        except Exception as e:
            print(f"[ERROR] Failed to read from log file: {e}", file=sys.stderr)
            self.open_file()
            return []


class SSEHandler(BaseHTTPRequestHandler):
    """HTTP handler for SSE log streaming."""
    
    log_follower = None
    
    def log_message(self, format, *args):
        """Suppress default logging to avoid cluttering output."""
        pass
    
    def send_sse_headers(self):
        """Send SSE-specific headers."""
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
    
    def send_sse_event(self, data, event_type='message'):
        """Send an SSE event."""
        try:
            message = f"event: {event_type}\ndata: {data}\n\n"
            self.wfile.write(message.encode('utf-8'))
            self.wfile.flush()
        except Exception as e:
            print(f"[ERROR] Failed to send SSE event: {e}", file=sys.stderr)
            raise
    
    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/logs/stream':
            self.handle_log_stream()
        elif self.path == '/health':
            self.handle_health()
        elif self.path == '/':
            self.handle_status()
        else:
            self.send_error(404, "Not Found")
    
    def handle_log_stream(self):
        """Stream log entries via SSE."""
        try:
            self.send_sse_headers()
            
            # Send initial connection event
            self.send_sse_event(json.dumps({
                'message': 'Connected to log stream',
                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
            }), 'connected')
            
            # Stream log entries
            while True:
                lines = self.log_follower.read_new_lines()
                for line in lines:
                    if line.strip():
                        self.send_sse_event(line)
                
                # Sleep briefly to avoid busy-waiting
                time.sleep(0.1)
                
        except (BrokenPipeError, ConnectionResetError):
            # Client disconnected
            pass
        except Exception as e:
            print(f"[ERROR] Error in log stream handler: {e}", file=sys.stderr)
    
    def handle_health(self):
        """Handle health check endpoint."""
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        health = {
            'status': 'healthy',
            'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        }
        self.wfile.write(json.dumps(health).encode('utf-8'))
    
    def handle_status(self):
        """Handle status page."""
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Parrot MCP Server - Log Stream</title>
            <style>
                body { font-family: monospace; margin: 2em; background: #1e1e1e; color: #d4d4d4; }
                h1 { color: #4ec9b0; }
                pre { background: #252526; padding: 1em; border-radius: 4px; overflow-x: auto; }
                .log-entry { margin: 0.5em 0; padding: 0.5em; background: #2d2d30; border-radius: 3px; }
                .error { color: #f48771; }
                .success { color: #4ec9b0; }
            </style>
        </head>
        <body>
            <h1>Parrot MCP Server - Log Stream</h1>
            <p>Real-time log streaming via Server-Sent Events (SSE)</p>
            
            <h2>Endpoints:</h2>
            <pre>
GET /logs/stream - SSE stream of log entries
GET /health      - Health check endpoint
GET /            - This status page
            </pre>
            
            <h2>Usage Example:</h2>
            <pre>
# Using curl
curl -N http://localhost:8080/logs/stream

# Using JavaScript
const eventSource = new EventSource('http://localhost:8080/logs/stream');
eventSource.onmessage = (event) => {
    const logEntry = JSON.parse(event.data);
    console.log(logEntry);
};
            </pre>
            
            <h2>Live Stream:</h2>
            <div id="log-container"></div>
            
            <script>
                const container = document.getElementById('log-container');
                const eventSource = new EventSource('/logs/stream');
                
                eventSource.onmessage = (event) => {
                    const div = document.createElement('div');
                    div.className = 'log-entry';
                    try {
                        const data = JSON.parse(event.data);
                        div.textContent = JSON.stringify(data, null, 2);
                        if (data.level === 'ERROR') div.classList.add('error');
                        if (data.status === 'success') div.classList.add('success');
                    } catch {
                        div.textContent = event.data;
                    }
                    container.insertBefore(div, container.firstChild);
                    // Keep only last 50 entries
                    while (container.children.length > 50) {
                        container.removeChild(container.lastChild);
                    }
                };
                
                eventSource.onerror = () => {
                    const div = document.createElement('div');
                    div.className = 'log-entry error';
                    div.textContent = 'Connection lost. Reconnecting...';
                    container.insertBefore(div, container.firstChild);
                };
            </script>
        </body>
        </html>
        """
        self.wfile.write(html.encode('utf-8'))


def parse_args():
    """Parse command line arguments."""
    log_file = './logs/parrot.log'
    port = 8080
    host = '0.0.0.0'
    
    for arg in sys.argv[1:]:
        if arg.startswith('--log-file='):
            log_file = arg.split('=', 1)[1]
        elif arg.startswith('--port='):
            port = int(arg.split('=', 1)[1])
        elif arg.startswith('--host='):
            host = arg.split('=', 1)[1]
        elif arg in ('--help', '-h'):
            print(__doc__)
            sys.exit(0)
        else:
            print(f"Unknown option: {arg}", file=sys.stderr)
            print("Use --help for usage information.", file=sys.stderr)
            sys.exit(1)
    
    return log_file, port, host


def main():
    """Main entry point."""
    log_file, port, host = parse_args()
    
    # Initialize log follower
    SSEHandler.log_follower = LogFollower(log_file)
    
    # Start HTTP server
    server = HTTPServer((host, port), SSEHandler)
    print(f"[INFO] Log streaming server started on http://{host}:{port}")
    print(f"[INFO] Following log file: {log_file}")
    print(f"[INFO] SSE endpoint: http://{host}:{port}/logs/stream")
    print(f"[INFO] Status page: http://{host}:{port}/")
    print(f"[INFO] Press Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[INFO] Server stopped")
        sys.exit(0)


if __name__ == '__main__':
    main()
