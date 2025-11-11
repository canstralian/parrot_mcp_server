#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
parrot_mcp_server/core/config.py

Application configuration management for Parrot MCP Server.
Loads environment variables, applies defaults, and enforces type safety.
"""

from functools import lru_cache
from typing import Literal

from pydantic import AnyUrl, Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # ─────────────────────────────────────────────
    # Server Configuration
    # ─────────────────────────────────────────────
    app_name: str = Field("Parrot_MCP_Server", description="Name of the application")
    app_env: Literal["development", "staging", "production"] = Field("development", description="Environment: development | staging | production")
    app_debug: bool = Field(True, description="Enable debug mode")
    host: str = Field("0.0.0.0", description="Host address to bind server")
    port: int = Field(8000, description="Port for the API server")

    # ─────────────────────────────────────────────
    # Logging & Telemetry
    # ─────────────────────────────────────────────
    log_level: str = Field("info", description="Log verbosity level")
    log_format: str = Field("json", description="Log output format (json | text)")
    enable_metrics: bool = Field(True, description="Enable Prometheus metrics endpoint")
    metrics_port: int = Field(9100, description="Port for metrics endpoint")

    # ─────────────────────────────────────────────
    # API Behavior / Limits
    # ─────────────────────────────────────────────
    request_timeout: int = Field(30, description="API request timeout in seconds")
    max_concurrent_tasks: int = Field(10, description="Maximum concurrent background tasks")
    cache_ttl: int = Field(300, description="Default cache time-to-live in seconds")
    enable_rate_limit: bool = Field(True, description="Enable rate limiting")
    rate_limit: int = Field(100, description="Requests per minute per client")

    # ─────────────────────────────────────────────
    # Database Configuration (non-sensitive)
    # ─────────────────────────────────────────────
    db_host: str = Field("db", description="Database hostname")
    db_port: int = Field(5432, description="Database port")
    db_name: str = Field("parrot_mcp", description="Database name")
    db_pool_size: int = Field(10, description="Database connection pool size")
    db_ssl_mode: Literal["disable", "allow", "prefer", "require", "verify-ca", "verify-full"] = Field("prefer", description="Postgres SSL mode")

    # ─────────────────────────────────────────────
    # AI / Model Integration
    # ─────────────────────────────────────────────
    default_model: str = Field("qwen-coder-32b", description="Default model identifier")
    enable_hf_models: bool = Field(True, description="Enable Hugging Face models")
    hf_model_cache_dir: str = Field("/app/models", description="Cache directory for model weights")
    max_generation_tokens: int = Field(2048, description="Maximum generation token count")
    temperature: float = Field(0.7, description="Default sampling temperature")
    top_p: float = Field(0.95, description="Nucleus sampling probability")

    # ─────────────────────────────────────────────
    # GitHub / CI Context
    # ─────────────────────────────────────────────
    github_org: str = Field("canstralian", description="GitHub organization name")
    github_repo: str = Field("parrot_mcp_server", description="Repository name")
    github_branch: str = Field("main", description="Default branch for CI/CD")
    enable_ci_validation: bool = Field(True, description="Enable CI validation workflows")

    # ─────────────────────────────────────────────
    # Cloudflare Gateway / Edge Integration
    # ─────────────────────────────────────────────
    cf_gateway_route: str = Field("/v1/parrot", description="Cloudflare Gateway route")
    cf_edge_mode: str = Field("compat", description="Cloudflare AI edge mode")
    cf_worker_namespace: str = Field("ai", description="Cloudflare worker namespace")
    cf_ai_endpoint: AnyUrl = Field("https://gateway.ai.cloudflare.com", description="Cloudflare AI endpoint")

    # ─────────────────────────────────────────────
    # Taskade / Automation
    # ─────────────────────────────────────────────
    taskade_project_name: str = Field("Parrot_Agent_Logs", description="Taskade project for logs")
    taskade_sync_interval: int = Field(300, description="Sync interval in seconds")
    enable_taskade_sync: bool = Field(True, description="Enable Taskade sync")

    # ─────────────────────────────────────────────
    # MCP Server Configuration
    # ─────────────────────────────────────────────
    mcp_namespace: str = Field("parrot", description="Namespace for MCP discovery")
    mcp_api_prefix: str = Field("/mcp", description="API prefix for MCP routes")
    mcp_enable_discovery: bool = Field(True, description="Enable MCP auto-discovery")
    mcp_autoload_tools: bool = Field(True, description="Autoload MCP tool registry on startup")
    mcp_registry_path: str = Field("/app/registry/tools.yml", description="Path to MCP tool registry")

    # ─────────────────────────────────────────────
    # Internal Networking / Clustering
    # ─────────────────────────────────────────────
    node_role: str = Field("primary", description="Node role: primary | worker")
    node_cluster_name: str = Field("parrot_cluster", description="Cluster name")
    heartbeat_interval: int = Field(10, description="Cluster heartbeat interval (seconds)")
    discovery_mode: str = Field("static", description="Cluster discovery mode (static | dynamic)")

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    """Return a cached Settings instance."""
    return Settings()
