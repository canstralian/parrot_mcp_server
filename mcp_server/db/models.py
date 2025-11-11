"""
Database models for enterprise-grade Nmap MCP Server.

This module defines the SQLAlchemy models for storing scan results,
user information, audit logs, and configuration.
"""

from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
from enum import Enum
import json

db = SQLAlchemy()


class ScanStatus(str, Enum):
    """Enumeration for scan task status"""
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class ScanType(str, Enum):
    """Enumeration for supported scan types"""
    DEFAULT = "default"
    QUICK = "quick"
    FULL = "full"
    STEALTH = "stealth"
    OS_DETECTION = "os"
    VULNERABILITY = "vuln"
    CUSTOM = "custom"


class User(db.Model):
    """User model for authentication and authorization"""
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    username = db.Column(db.String(80), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    api_key = db.Column(db.String(64), unique=True, nullable=True, index=True)
    role = db.Column(db.String(20), nullable=False, default="user")  # admin, analyst, user
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_login = db.Column(db.DateTime, nullable=True)

    # Relationships
    scans = db.relationship("ScanResult", back_populates="user", lazy="dynamic")
    audit_logs = db.relationship("AuditLog", back_populates="user", lazy="dynamic")

    def __repr__(self):
        return f"<User {self.username}>"

    def to_dict(self):
        """Convert user to dictionary (excluding sensitive data)"""
        return {
            "id": self.id,
            "username": self.username,
            "email": self.email,
            "role": self.role,
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "last_login": self.last_login.isoformat() if self.last_login else None
        }


class ScanResult(db.Model):
    """Model for storing Nmap scan results"""
    __tablename__ = "scan_results"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    task_id = db.Column(db.String(100), unique=True, nullable=True, index=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)

    # Scan parameters
    target = db.Column(db.String(255), nullable=False, index=True)
    scan_type = db.Column(db.String(50), nullable=False)
    scan_args = db.Column(db.Text, nullable=True)  # JSON string of additional args

    # Scan status and timing
    status = db.Column(db.String(20), nullable=False, default=ScanStatus.QUEUED.value)
    priority = db.Column(db.Integer, default=5)  # 1-10, higher = more priority
    started_at = db.Column(db.DateTime, nullable=True)
    completed_at = db.Column(db.DateTime, nullable=True)
    duration_seconds = db.Column(db.Float, nullable=True)

    # Results
    raw_output = db.Column(db.Text, nullable=True)
    parsed_results = db.Column(db.Text, nullable=True)  # JSON string
    error_message = db.Column(db.Text, nullable=True)

    # Metadata
    hosts_up = db.Column(db.Integer, default=0)
    ports_found = db.Column(db.Integer, default=0)
    vulnerabilities_found = db.Column(db.Integer, default=0)

    # Audit
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = db.relationship("User", back_populates="scans")
    reports = db.relationship("ScanReport", back_populates="scan", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<ScanResult {self.id}: {self.target} ({self.status})>"

    def to_dict(self, include_results=False):
        """Convert scan to dictionary"""
        data = {
            "id": self.id,
            "task_id": self.task_id,
            "user_id": self.user_id,
            "target": self.target,
            "scan_type": self.scan_type,
            "status": self.status,
            "priority": self.priority,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "duration_seconds": self.duration_seconds,
            "hosts_up": self.hosts_up,
            "ports_found": self.ports_found,
            "vulnerabilities_found": self.vulnerabilities_found,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

        if include_results:
            data.update({
                "raw_output": self.raw_output,
                "parsed_results": json.loads(self.parsed_results) if self.parsed_results else None,
                "error_message": self.error_message,
                "scan_args": json.loads(self.scan_args) if self.scan_args else None,
            })

        return data

    def save(self):
        """Save the scan result to database"""
        db.session.add(self)
        db.session.commit()

    def update_status(self, status, error_message=None):
        """Update scan status"""
        self.status = status
        self.updated_at = datetime.utcnow()

        if status == ScanStatus.RUNNING.value and not self.started_at:
            self.started_at = datetime.utcnow()
        elif status in [ScanStatus.COMPLETED.value, ScanStatus.FAILED.value]:
            self.completed_at = datetime.utcnow()
            if self.started_at:
                self.duration_seconds = (self.completed_at - self.started_at).total_seconds()

        if error_message:
            self.error_message = error_message

        db.session.commit()


class ScanReport(db.Model):
    """Model for generated scan reports in various formats"""
    __tablename__ = "scan_reports"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    scan_id = db.Column(db.Integer, db.ForeignKey("scan_results.id"), nullable=False)
    format = db.Column(db.String(20), nullable=False)  # json, csv, html, pdf
    file_path = db.Column(db.String(500), nullable=False)
    file_size_bytes = db.Column(db.Integer, nullable=True)
    generated_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    expires_at = db.Column(db.DateTime, nullable=True)

    # Relationships
    scan = db.relationship("ScanResult", back_populates="reports")

    def __repr__(self):
        return f"<ScanReport {self.id}: {self.format}>"

    def to_dict(self):
        return {
            "id": self.id,
            "scan_id": self.scan_id,
            "format": self.format,
            "file_path": self.file_path,
            "file_size_bytes": self.file_size_bytes,
            "generated_at": self.generated_at.isoformat() if self.generated_at else None,
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
        }


class AuditLog(db.Model):
    """Model for audit logging all API activities"""
    __tablename__ = "audit_logs"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    action = db.Column(db.String(100), nullable=False, index=True)
    resource_type = db.Column(db.String(50), nullable=True)  # scan, user, report
    resource_id = db.Column(db.Integer, nullable=True)
    ip_address = db.Column(db.String(45), nullable=True)  # IPv6 support
    user_agent = db.Column(db.String(500), nullable=True)
    status_code = db.Column(db.Integer, nullable=True)
    details = db.Column(db.Text, nullable=True)  # JSON string
    timestamp = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Relationships
    user = db.relationship("User", back_populates="audit_logs")

    def __repr__(self):
        return f"<AuditLog {self.id}: {self.action}>"

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "action": self.action,
            "resource_type": self.resource_type,
            "resource_id": self.resource_id,
            "ip_address": self.ip_address,
            "user_agent": self.user_agent,
            "status_code": self.status_code,
            "details": json.loads(self.details) if self.details else None,
            "timestamp": self.timestamp.isoformat() if self.timestamp else None,
        }

    @staticmethod
    def log(user_id, action, resource_type=None, resource_id=None,
            ip_address=None, user_agent=None, status_code=None, details=None):
        """Create an audit log entry"""
        log_entry = AuditLog(
            user_id=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            ip_address=ip_address,
            user_agent=user_agent,
            status_code=status_code,
            details=json.dumps(details) if details else None
        )
        db.session.add(log_entry)
        db.session.commit()
        return log_entry


class SystemConfig(db.Model):
    """Model for storing system configuration"""
    __tablename__ = "system_config"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    key = db.Column(db.String(100), unique=True, nullable=False, index=True)
    value = db.Column(db.Text, nullable=True)
    value_type = db.Column(db.String(20), default="string")  # string, int, bool, json
    description = db.Column(db.String(500), nullable=True)
    is_secret = db.Column(db.Boolean, default=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    updated_by = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    def __repr__(self):
        return f"<SystemConfig {self.key}>"

    def get_value(self):
        """Get typed value"""
        if self.value is None:
            return None

        if self.value_type == "int":
            return int(self.value)
        elif self.value_type == "bool":
            return self.value.lower() in ["true", "1", "yes"]
        elif self.value_type == "json":
            return json.loads(self.value)
        else:
            return self.value

    def to_dict(self):
        return {
            "id": self.id,
            "key": self.key,
            "value": "***" if self.is_secret else self.get_value(),
            "value_type": self.value_type,
            "description": self.description,
            "is_secret": self.is_secret,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
