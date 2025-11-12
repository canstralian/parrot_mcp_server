"""Configuration management for Parrot MCP Server"""

import os
from datetime import timedelta


class Config:
    """Base configuration class"""

    # Flask
    SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-key-change-in-production")
    DEBUG = os.getenv("APP_DEBUG", "false").lower() == "true"
    TESTING = False

    # Server
    HOST = os.getenv("HOST", "0.0.0.0")
    PORT = int(os.getenv("PORT", 8000))

    # Database
    SQLALCHEMY_DATABASE_URI = os.getenv(
        "DATABASE_URL",
        f"postgresql://{os.getenv('DB_USER', 'parrot')}:"
        f"{os.getenv('DB_PASSWORD', 'parrot')}@"
        f"{os.getenv('DB_HOST', 'localhost')}:"
        f"{os.getenv('DB_PORT', '5432')}/"
        f"{os.getenv('DB_NAME', 'parrot_mcp')}"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_POOL_SIZE = int(os.getenv("DB_POOL_SIZE", 10))
    SQLALCHEMY_POOL_TIMEOUT = 30
    SQLALCHEMY_POOL_RECYCLE = 1800

    # Redis/Celery
    REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", REDIS_URL)
    CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", REDIS_URL)

    # Security
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY", SECRET_KEY)
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=1)
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=30)
    JWT_ALGORITHM = "HS256"

    # Password hashing
    BCRYPT_LOG_ROUNDS = 12

    # Rate Limiting
    RATELIMIT_ENABLED = os.getenv("ENABLE_RATE_LIMIT", "true").lower() == "true"
    RATELIMIT_STORAGE_URL = REDIS_URL
    RATELIMIT_DEFAULT = os.getenv("RATE_LIMIT", "100 per hour")
    RATELIMIT_HEADERS_ENABLED = True

    # API
    API_TITLE = "Parrot MCP Server - Nmap Integration"
    API_VERSION = "v1"
    OPENAPI_VERSION = "3.0.2"
    API_PREFIX = os.getenv("MCP_API_PREFIX", "/api/v1")

    # Nmap
    NMAP_PATH = os.getenv("NMAP_PATH", "/usr/bin/nmap")
    NMAP_TIMEOUT = int(os.getenv("NMAP_TIMEOUT", 300))  # seconds
    MAX_CONCURRENT_SCANS = int(os.getenv("MAX_CONCURRENT_TASKS", 10))

    # Logging
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
    LOG_FORMAT = os.getenv("LOG_FORMAT", "json")
    LOG_FILE = os.getenv("LOG_FILE", "./logs/mcp_server.log")

    # File Storage
    REPORT_STORAGE_PATH = os.getenv("REPORT_STORAGE_PATH", "./reports")
    REPORT_MAX_AGE_DAYS = int(os.getenv("REPORT_MAX_AGE_DAYS", 30))

    # Metrics
    ENABLE_METRICS = os.getenv("ENABLE_METRICS", "true").lower() == "true"
    METRICS_PORT = int(os.getenv("METRICS_PORT", 9100))

    # CORS
    CORS_ENABLED = os.getenv("CORS_ENABLED", "false").lower() == "true"
    CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*").split(",")


class DevelopmentConfig(Config):
    """Development configuration"""
    DEBUG = True
    TESTING = False


class ProductionConfig(Config):
    """Production configuration"""
    DEBUG = False
    TESTING = False

    # Override with stricter settings
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(minutes=15)
    BCRYPT_LOG_ROUNDS = 14


class TestingConfig(Config):
    """Testing configuration"""
    TESTING = True
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    CELERY_TASK_ALWAYS_EAGER = True
    CELERY_TASK_EAGER_PROPAGATES = True


# Configuration dictionary
config_by_name = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
    "default": DevelopmentConfig
}


def get_config(env_name: str = None) -> Config:
    """
    Get configuration based on environment name.

    Args:
        env_name: Environment name (development, production, testing)

    Returns:
        Configuration class
    """
    if env_name is None:
        env_name = os.getenv("APP_ENV", "development")

    return config_by_name.get(env_name, DevelopmentConfig)
