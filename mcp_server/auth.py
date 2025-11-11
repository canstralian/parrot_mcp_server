"""
Authentication and authorization module for Parrot MCP Server.

Provides JWT-based authentication, role-based access control (RBAC),
and API key authentication.
"""

import secrets
import hashlib
from functools import wraps
from datetime import datetime
from flask import request, jsonify, g
from werkzeug.security import generate_password_hash, check_password_hash
import jwt

from mcp_server.db import User, AuditLog, db


class AuthenticationError(Exception):
    """Raised when authentication fails"""
    pass


class AuthorizationError(Exception):
    """Raised when authorization fails"""
    pass


class Role:
    """Role definitions"""
    ADMIN = "admin"
    ANALYST = "analyst"
    USER = "user"

    @classmethod
    def all(cls):
        return [cls.ADMIN, cls.ANALYST, cls.USER]

    @classmethod
    def hierarchy(cls):
        """Role hierarchy for permission checking"""
        return {
            cls.ADMIN: 3,
            cls.ANALYST: 2,
            cls.USER: 1
        }


class Permission:
    """Permission definitions"""
    # Scan permissions
    SCAN_CREATE = "scan:create"
    SCAN_READ = "scan:read"
    SCAN_READ_ALL = "scan:read:all"
    SCAN_DELETE = "scan:delete"
    SCAN_DELETE_ALL = "scan:delete:all"

    # User permissions
    USER_CREATE = "user:create"
    USER_READ = "user:read"
    USER_UPDATE = "user:update"
    USER_DELETE = "user:delete"

    # Report permissions
    REPORT_CREATE = "report:create"
    REPORT_READ = "report:read"
    REPORT_DELETE = "report:delete"

    # System permissions
    SYSTEM_CONFIG = "system:config"
    SYSTEM_AUDIT = "system:audit"


# Role to permissions mapping
ROLE_PERMISSIONS = {
    Role.ADMIN: [
        Permission.SCAN_CREATE,
        Permission.SCAN_READ,
        Permission.SCAN_READ_ALL,
        Permission.SCAN_DELETE,
        Permission.SCAN_DELETE_ALL,
        Permission.USER_CREATE,
        Permission.USER_READ,
        Permission.USER_UPDATE,
        Permission.USER_DELETE,
        Permission.REPORT_CREATE,
        Permission.REPORT_READ,
        Permission.REPORT_DELETE,
        Permission.SYSTEM_CONFIG,
        Permission.SYSTEM_AUDIT,
    ],
    Role.ANALYST: [
        Permission.SCAN_CREATE,
        Permission.SCAN_READ,
        Permission.SCAN_READ_ALL,
        Permission.SCAN_DELETE,
        Permission.REPORT_CREATE,
        Permission.REPORT_READ,
        Permission.USER_READ,
    ],
    Role.USER: [
        Permission.SCAN_CREATE,
        Permission.SCAN_READ,
        Permission.REPORT_CREATE,
        Permission.REPORT_READ,
    ]
}


class AuthService:
    """Authentication service"""

    @staticmethod
    def hash_password(password: str) -> str:
        """Hash password using werkzeug"""
        return generate_password_hash(password)

    @staticmethod
    def verify_password(password: str, password_hash: str) -> bool:
        """Verify password against hash"""
        return check_password_hash(password_hash, password)

    @staticmethod
    def generate_api_key() -> str:
        """Generate a secure API key"""
        return secrets.token_urlsafe(32)

    @staticmethod
    def hash_api_key(api_key: str) -> str:
        """Hash API key for storage"""
        return hashlib.sha256(api_key.encode()).hexdigest()

    @staticmethod
    def create_user(username: str, email: str, password: str, role: str = Role.USER) -> User:
        """
        Create a new user.

        Args:
            username: Username
            email: Email address
            password: Plain text password
            role: User role

        Returns:
            User object

        Raises:
            ValueError: If validation fails
        """
        # Validate role
        if role not in Role.all():
            raise ValueError(f"Invalid role: {role}")

        # Check if user exists
        if User.query.filter_by(username=username).first():
            raise ValueError(f"Username {username} already exists")

        if User.query.filter_by(email=email).first():
            raise ValueError(f"Email {email} already exists")

        # Create user
        user = User(
            username=username,
            email=email,
            password_hash=AuthService.hash_password(password),
            role=role,
            is_active=True
        )

        db.session.add(user)
        db.session.commit()

        return user

    @staticmethod
    def authenticate_user(username: str, password: str) -> User:
        """
        Authenticate user with username and password.

        Args:
            username: Username
            password: Password

        Returns:
            User object if authenticated

        Raises:
            AuthenticationError: If authentication fails
        """
        user = User.query.filter_by(username=username).first()

        if not user or not user.is_active:
            raise AuthenticationError("Invalid credentials")

        if not AuthService.verify_password(password, user.password_hash):
            raise AuthenticationError("Invalid credentials")

        # Update last login
        user.last_login = datetime.utcnow()
        db.session.commit()

        return user

    @staticmethod
    def authenticate_api_key(api_key: str) -> User:
        """
        Authenticate user with API key.

        Args:
            api_key: API key

        Returns:
            User object if authenticated

        Raises:
            AuthenticationError: If authentication fails
        """
        # Note: In production, hash the API key before querying
        user = User.query.filter_by(api_key=api_key).first()

        if not user or not user.is_active:
            raise AuthenticationError("Invalid API key")

        return user

    @staticmethod
    def generate_tokens(user: User, app_config) -> dict:
        """
        Generate JWT access and refresh tokens.

        Args:
            user: User object
            app_config: Flask app config

        Returns:
            Dict with access_token and refresh_token
        """
        access_token_payload = {
            "user_id": user.id,
            "username": user.username,
            "role": user.role,
            "type": "access",
            "exp": datetime.utcnow() + app_config.JWT_ACCESS_TOKEN_EXPIRES
        }

        refresh_token_payload = {
            "user_id": user.id,
            "type": "refresh",
            "exp": datetime.utcnow() + app_config.JWT_REFRESH_TOKEN_EXPIRES
        }

        access_token = jwt.encode(
            access_token_payload,
            app_config.JWT_SECRET_KEY,
            algorithm=app_config.JWT_ALGORITHM
        )

        refresh_token = jwt.encode(
            refresh_token_payload,
            app_config.JWT_SECRET_KEY,
            algorithm=app_config.JWT_ALGORITHM
        )

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_in": int(app_config.JWT_ACCESS_TOKEN_EXPIRES.total_seconds())
        }

    @staticmethod
    def verify_token(token: str, app_config) -> dict:
        """
        Verify and decode JWT token.

        Args:
            token: JWT token
            app_config: Flask app config

        Returns:
            Decoded token payload

        Raises:
            AuthenticationError: If token is invalid
        """
        try:
            payload = jwt.decode(
                token,
                app_config.JWT_SECRET_KEY,
                algorithms=[app_config.JWT_ALGORITHM]
            )
            return payload
        except jwt.ExpiredSignatureError:
            raise AuthenticationError("Token has expired")
        except jwt.InvalidTokenError:
            raise AuthenticationError("Invalid token")


class AuthorizationService:
    """Authorization service for RBAC"""

    @staticmethod
    def has_permission(user: User, permission: str) -> bool:
        """
        Check if user has a specific permission.

        Args:
            user: User object
            permission: Permission string

        Returns:
            True if user has permission
        """
        user_permissions = ROLE_PERMISSIONS.get(user.role, [])
        return permission in user_permissions

    @staticmethod
    def has_any_permission(user: User, permissions: list) -> bool:
        """Check if user has any of the specified permissions"""
        return any(AuthorizationService.has_permission(user, p) for p in permissions)

    @staticmethod
    def has_all_permissions(user: User, permissions: list) -> bool:
        """Check if user has all of the specified permissions"""
        return all(AuthorizationService.has_permission(user, p) for p in permissions)

    @staticmethod
    def can_access_resource(user: User, resource_user_id: int, permission: str) -> bool:
        """
        Check if user can access a resource owned by another user.

        Args:
            user: Current user
            resource_user_id: User ID of resource owner
            permission: Required permission

        Returns:
            True if access is allowed
        """
        # User can always access their own resources
        if user.id == resource_user_id:
            return True

        # Check if user has the "all" version of the permission
        return AuthorizationService.has_permission(user, permission)


# Decorators

def token_required(f):
    """Decorator to require JWT token authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = None
        auth_header = request.headers.get("Authorization")

        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]

        if not token:
            return jsonify({"error": "Token is missing"}), 401

        try:
            from flask import current_app
            payload = AuthService.verify_token(token, current_app.config)

            # Get user from database
            user = User.query.get(payload["user_id"])
            if not user or not user.is_active:
                return jsonify({"error": "User not found or inactive"}), 401

            # Store user in request context
            g.current_user = user

        except AuthenticationError as e:
            return jsonify({"error": str(e)}), 401

        return f(*args, **kwargs)

    return decorated_function


def api_key_required(f):
    """Decorator to require API key authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        api_key = request.headers.get("X-API-Key")

        if not api_key:
            return jsonify({"error": "API key is missing"}), 401

        try:
            user = AuthService.authenticate_api_key(api_key)
            g.current_user = user

        except AuthenticationError as e:
            return jsonify({"error": str(e)}), 401

        return f(*args, **kwargs)

    return decorated_function


def auth_required(f):
    """Decorator to accept either JWT token or API key"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Try API key first
        api_key = request.headers.get("X-API-Key")
        if api_key:
            try:
                user = AuthService.authenticate_api_key(api_key)
                g.current_user = user
                return f(*args, **kwargs)
            except AuthenticationError:
                pass

        # Try JWT token
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]
            try:
                from flask import current_app
                payload = AuthService.verify_token(token, current_app.config)
                user = User.query.get(payload["user_id"])
                if user and user.is_active:
                    g.current_user = user
                    return f(*args, **kwargs)
            except AuthenticationError:
                pass

        return jsonify({"error": "Authentication required"}), 401

    return decorated_function


def permission_required(*permissions):
    """Decorator to require specific permissions"""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not hasattr(g, "current_user"):
                return jsonify({"error": "Authentication required"}), 401

            user = g.current_user

            # Check if user has any of the required permissions
            if not AuthorizationService.has_any_permission(user, list(permissions)):
                return jsonify({
                    "error": "Insufficient permissions",
                    "required": list(permissions)
                }), 403

            return f(*args, **kwargs)

        return decorated_function
    return decorator


def role_required(*roles):
    """Decorator to require specific roles"""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not hasattr(g, "current_user"):
                return jsonify({"error": "Authentication required"}), 401

            user = g.current_user

            if user.role not in roles:
                return jsonify({
                    "error": "Insufficient role",
                    "required": list(roles)
                }), 403

            return f(*args, **kwargs)

        return decorated_function
    return decorator
