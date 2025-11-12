"""
Enterprise-grade Flask application for Parrot MCP Server with Nmap integration.

This module provides a production-ready REST API with:
- JWT and API key authentication
- Role-based access control (RBAC)
- Rate limiting
- Comprehensive audit logging
- Asynchronous scan execution with Celery
"""

import os
import json
import logging
from datetime import datetime
from flask import Flask, request, jsonify, g
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_cors import CORS
from werkzeug.exceptions import HTTPException

from mcp_server.config import get_config
from mcp_server.db import db, User, ScanResult, ScanReport, AuditLog, ScanStatus, ScanType
from mcp_server.auth import (
    AuthService,
    AuthorizationService,
    AuthenticationError,
    AuthorizationError,
    auth_required,
    token_required,
    permission_required,
    role_required,
    Role,
    Permission
)
from mcp_server.worker import execute_scan_task

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def create_app(config_name=None):
    """
    Application factory pattern.

    Args:
        config_name: Configuration name (development, production, testing)

    Returns:
        Flask application instance
    """
    app = Flask(__name__)

    # Load configuration
    config = get_config(config_name)
    app.config.from_object(config)

    # Initialize extensions
    db.init_app(app)

    # CORS
    if app.config.get("CORS_ENABLED"):
        CORS(app, origins=app.config.get("CORS_ORIGINS"))

    # Rate limiting
    limiter = Limiter(
        app=app,
        key_func=get_remote_address,
        storage_uri=app.config.get("RATELIMIT_STORAGE_URL"),
        enabled=app.config.get("RATELIMIT_ENABLED", True)
    )

    # Create tables (in production, use migrations)
    with app.app_context():
        db.create_all()

    # Request logging and audit middleware
    @app.before_request
    def before_request():
        """Log request and prepare audit context"""
        g.request_start_time = datetime.utcnow()
        logger.info(f"{request.method} {request.path} from {request.remote_addr}")

    @app.after_request
    def after_request(response):
        """Log response and create audit log"""
        if hasattr(g, "request_start_time"):
            duration = (datetime.utcnow() - g.request_start_time).total_seconds()
            logger.info(
                f"{request.method} {request.path} - "
                f"Status: {response.status_code} - "
                f"Duration: {duration:.3f}s"
            )

        # Create audit log for important actions
        if hasattr(g, "current_user") and request.method in ["POST", "PUT", "DELETE"]:
            try:
                AuditLog.log(
                    user_id=g.current_user.id,
                    action=f"{request.method} {request.path}",
                    ip_address=request.remote_addr,
                    user_agent=request.user_agent.string,
                    status_code=response.status_code,
                    details={"path": request.path, "method": request.method}
                )
            except Exception as e:
                logger.error(f"Failed to create audit log: {str(e)}")

        return response

    # Error handlers
    @app.errorhandler(HTTPException)
    def handle_http_exception(e):
        """Handle HTTP exceptions"""
        response = {
            "error": e.name,
            "message": e.description,
            "status_code": e.code
        }
        return jsonify(response), e.code

    @app.errorhandler(Exception)
    def handle_exception(e):
        """Handle unexpected exceptions"""
        logger.exception("Unhandled exception")
        response = {
            "error": "Internal Server Error",
            "message": str(e) if app.debug else "An unexpected error occurred"
        }
        return jsonify(response), 500

    # Health check endpoint
    @app.route("/health", methods=["GET"])
    def health_check():
        """Health check endpoint"""
        return jsonify({
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": app.config.get("API_VERSION", "v1")
        })

    # Authentication endpoints
    @app.route(f"{app.config['API_PREFIX']}/auth/register", methods=["POST"])
    @limiter.limit("5 per hour")
    def register():
        """Register a new user"""
        data = request.get_json()

        required_fields = ["username", "email", "password"]
        if not all(field in data for field in required_fields):
            return jsonify({"error": "Missing required fields"}), 400

        try:
            user = AuthService.create_user(
                username=data["username"],
                email=data["email"],
                password=data["password"],
                role=data.get("role", Role.USER)
            )

            return jsonify({
                "message": "User created successfully",
                "user": user.to_dict()
            }), 201

        except ValueError as e:
            return jsonify({"error": str(e)}), 400

    @app.route(f"{app.config['API_PREFIX']}/auth/login", methods=["POST"])
    @limiter.limit("10 per minute")
    def login():
        """Login and get JWT tokens"""
        data = request.get_json()

        if not data.get("username") or not data.get("password"):
            return jsonify({"error": "Username and password required"}), 400

        try:
            user = AuthService.authenticate_user(
                username=data["username"],
                password=data["password"]
            )

            tokens = AuthService.generate_tokens(user, app.config)

            return jsonify({
                "message": "Login successful",
                "user": user.to_dict(),
                **tokens
            }), 200

        except AuthenticationError as e:
            return jsonify({"error": str(e)}), 401

    @app.route(f"{app.config['API_PREFIX']}/auth/api-key", methods=["POST"])
    @token_required
    def generate_api_key():
        """Generate a new API key for current user"""
        user = g.current_user

        # Generate new API key
        api_key = AuthService.generate_api_key()
        user.api_key = api_key
        db.session.commit()

        return jsonify({
            "message": "API key generated successfully",
            "api_key": api_key,
            "warning": "Store this key securely. It will not be shown again."
        }), 200

    # Scan endpoints
    @app.route(f"{app.config['API_PREFIX']}/scans", methods=["POST"])
    @auth_required
    @permission_required(Permission.SCAN_CREATE)
    @limiter.limit("20 per hour")
    def create_scan():
        """Create and queue a new Nmap scan"""
        data = request.get_json()

        # Validate required fields
        if not data.get("target"):
            return jsonify({"error": "Target is required"}), 400

        target = data.get("target")
        scan_type = data.get("scan_type", "default")
        custom_args = data.get("custom_args")
        priority = data.get("priority", 5)

        # Validate scan type
        if scan_type not in [t.value for t in ScanType]:
            return jsonify({
                "error": f"Invalid scan type. Allowed: {[t.value for t in ScanType]}"
            }), 400

        # Create scan record
        scan = ScanResult(
            user_id=g.current_user.id,
            target=target,
            scan_type=scan_type,
            scan_args=json.dumps(custom_args) if custom_args else None,
            status=ScanStatus.QUEUED.value,
            priority=priority
        )

        db.session.add(scan)
        db.session.commit()

        # Queue Celery task
        try:
            task = execute_scan_task.apply_async(
                args=[scan.id, target, scan_type, custom_args],
                priority=priority
            )

            scan.task_id = task.id
            db.session.commit()

            logger.info(f"Scan {scan.id} queued with task_id {task.id}")

            return jsonify({
                "message": "Scan queued successfully",
                "scan": scan.to_dict(),
                "task_id": task.id
            }), 202

        except Exception as e:
            logger.error(f"Failed to queue scan: {str(e)}")
            scan.update_status(ScanStatus.FAILED.value, error_message=str(e))
            return jsonify({"error": "Failed to queue scan"}), 500

    @app.route(f"{app.config['API_PREFIX']}/scans", methods=["GET"])
    @auth_required
    @permission_required(Permission.SCAN_READ)
    def list_scans():
        """List scans (filtered by user or all based on permissions)"""
        # Pagination
        page = request.args.get("page", 1, type=int)
        per_page = request.args.get("per_page", 20, type=int)
        per_page = min(per_page, 100)  # Max 100 per page

        # Filters
        status = request.args.get("status")
        scan_type = request.args.get("scan_type")

        # Build query
        query = ScanResult.query

        # Filter by user unless has permission to see all
        if not AuthorizationService.has_permission(g.current_user, Permission.SCAN_READ_ALL):
            query = query.filter_by(user_id=g.current_user.id)

        if status:
            query = query.filter_by(status=status)

        if scan_type:
            query = query.filter_by(scan_type=scan_type)

        # Order by creation date (newest first)
        query = query.order_by(ScanResult.created_at.desc())

        # Paginate
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)

        return jsonify({
            "scans": [scan.to_dict() for scan in pagination.items],
            "pagination": {
                "page": page,
                "per_page": per_page,
                "total": pagination.total,
                "pages": pagination.pages
            }
        }), 200

    @app.route(f"{app.config['API_PREFIX']}/scans/<int:scan_id>", methods=["GET"])
    @auth_required
    @permission_required(Permission.SCAN_READ)
    def get_scan(scan_id):
        """Get detailed scan results"""
        scan = ScanResult.query.get(scan_id)

        if not scan:
            return jsonify({"error": "Scan not found"}), 404

        # Check if user can access this scan
        if not AuthorizationService.can_access_resource(
            g.current_user, scan.user_id, Permission.SCAN_READ_ALL
        ):
            return jsonify({"error": "Access denied"}), 403

        # Include full results
        include_results = request.args.get("include_results", "true").lower() == "true"

        return jsonify({
            "scan": scan.to_dict(include_results=include_results)
        }), 200

    @app.route(f"{app.config['API_PREFIX']}/scans/<int:scan_id>", methods=["DELETE"])
    @auth_required
    @permission_required(Permission.SCAN_DELETE)
    def delete_scan(scan_id):
        """Delete a scan"""
        scan = ScanResult.query.get(scan_id)

        if not scan:
            return jsonify({"error": "Scan not found"}), 404

        # Check if user can delete this scan
        if not AuthorizationService.can_access_resource(
            g.current_user, scan.user_id, Permission.SCAN_DELETE_ALL
        ):
            return jsonify({"error": "Access denied"}), 403

        db.session.delete(scan)
        db.session.commit()

        return jsonify({"message": "Scan deleted successfully"}), 200

    @app.route(f"{app.config['API_PREFIX']}/scans/<int:scan_id>/cancel", methods=["POST"])
    @auth_required
    @permission_required(Permission.SCAN_DELETE)
    def cancel_scan(scan_id):
        """Cancel a running scan"""
        scan = ScanResult.query.get(scan_id)

        if not scan:
            return jsonify({"error": "Scan not found"}), 404

        # Check if user can cancel this scan
        if not AuthorizationService.can_access_resource(
            g.current_user, scan.user_id, Permission.SCAN_DELETE_ALL
        ):
            return jsonify({"error": "Access denied"}), 403

        # Can only cancel queued or running scans
        if scan.status not in [ScanStatus.QUEUED.value, ScanStatus.RUNNING.value]:
            return jsonify({"error": "Scan cannot be cancelled"}), 400

        # Revoke Celery task if exists
        if scan.task_id:
            from mcp_server.worker import celery_app
            celery_app.control.revoke(scan.task_id, terminate=True)

        scan.update_status(ScanStatus.CANCELLED.value)

        return jsonify({"message": "Scan cancelled successfully"}), 200

    # Statistics endpoint
    @app.route(f"{app.config['API_PREFIX']}/stats", methods=["GET"])
    @auth_required
    def get_statistics():
        """Get scan statistics"""
        from sqlalchemy import func

        # Base query
        query = ScanResult.query

        # Filter by user unless has permission to see all
        if not AuthorizationService.has_permission(g.current_user, Permission.SCAN_READ_ALL):
            query = query.filter_by(user_id=g.current_user.id)

        # Count by status
        status_counts = db.session.query(
            ScanResult.status,
            func.count(ScanResult.id)
        ).group_by(ScanResult.status)

        if not AuthorizationService.has_permission(g.current_user, Permission.SCAN_READ_ALL):
            status_counts = status_counts.filter_by(user_id=g.current_user.id)

        stats = {
            "total_scans": query.count(),
            "by_status": dict(status_counts.all()),
            "total_hosts_scanned": query.with_entities(
                func.sum(ScanResult.hosts_up)
            ).scalar() or 0,
            "total_ports_found": query.with_entities(
                func.sum(ScanResult.ports_found)
            ).scalar() or 0
        }

        return jsonify(stats), 200

    # Admin endpoints
    @app.route(f"{app.config['API_PREFIX']}/admin/users", methods=["GET"])
    @auth_required
    @role_required(Role.ADMIN)
    def list_users():
        """List all users (admin only)"""
        users = User.query.all()
        return jsonify({
            "users": [user.to_dict() for user in users]
        }), 200

    @app.route(f"{app.config['API_PREFIX']}/admin/audit-logs", methods=["GET"])
    @auth_required
    @permission_required(Permission.SYSTEM_AUDIT)
    def list_audit_logs():
        """List audit logs (admin only)"""
        page = request.args.get("page", 1, type=int)
        per_page = request.args.get("per_page", 50, type=int)

        pagination = AuditLog.query.order_by(
            AuditLog.timestamp.desc()
        ).paginate(page=page, per_page=per_page, error_out=False)

        return jsonify({
            "logs": [log.to_dict() for log in pagination.items],
            "pagination": {
                "page": page,
                "per_page": per_page,
                "total": pagination.total,
                "pages": pagination.pages
            }
        }), 200

    return app


# For running directly
if __name__ == "__main__":
    app = create_app()
    app.run(
        host=app.config["HOST"],
        port=app.config["PORT"],
        debug=app.config["DEBUG"]
    )
