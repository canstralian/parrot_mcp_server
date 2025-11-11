#!/usr/bin/env python3
"""
Database initialization script for Parrot MCP Server.

This script:
1. Creates all database tables
2. Creates an initial admin user
3. Sets up initial system configuration
"""

import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import click
from mcp_server.app import create_app
from mcp_server.db import db, User, SystemConfig
from mcp_server.auth import AuthService, Role


@click.command()
@click.option('--admin-username', default='admin', help='Admin username')
@click.option('--admin-email', default='admin@example.com', help='Admin email')
@click.option('--admin-password', prompt=True, hide_input=True,
              confirmation_prompt=True, help='Admin password')
@click.option('--drop-existing', is_flag=True, help='Drop existing tables')
def init_database(admin_username, admin_email, admin_password, drop_existing):
    """Initialize the database with tables and admin user."""

    click.echo("Initializing Parrot MCP Server database...")

    # Create Flask app
    app = create_app()

    with app.app_context():
        # Drop existing tables if requested
        if drop_existing:
            click.confirm('This will drop all existing tables. Continue?', abort=True)
            click.echo("Dropping existing tables...")
            db.drop_all()

        # Create tables
        click.echo("Creating database tables...")
        db.create_all()
        click.echo("✓ Database tables created")

        # Check if admin user already exists
        existing_admin = User.query.filter_by(username=admin_username).first()
        if existing_admin:
            click.echo(f"⚠ Admin user '{admin_username}' already exists. Skipping user creation.")
        else:
            # Create admin user
            click.echo(f"Creating admin user: {admin_username}")
            try:
                admin_user = AuthService.create_user(
                    username=admin_username,
                    email=admin_email,
                    password=admin_password,
                    role=Role.ADMIN
                )
                click.echo(f"✓ Admin user created successfully")
                click.echo(f"  Username: {admin_user.username}")
                click.echo(f"  Email: {admin_user.email}")
                click.echo(f"  Role: {admin_user.role}")
            except ValueError as e:
                click.echo(f"✗ Failed to create admin user: {str(e)}", err=True)
                sys.exit(1)

        # Create initial system configuration
        click.echo("Setting up system configuration...")

        configs = [
            {
                "key": "scan_retention_days",
                "value": "30",
                "value_type": "int",
                "description": "Number of days to retain scan results"
            },
            {
                "key": "max_scan_size",
                "value": "256",
                "value_type": "int",
                "description": "Maximum number of hosts in a single scan"
            },
            {
                "key": "enable_vulnerability_scans",
                "value": "true",
                "value_type": "bool",
                "description": "Enable vulnerability scanning features"
            }
        ]

        for config_data in configs:
            existing = SystemConfig.query.filter_by(key=config_data["key"]).first()
            if not existing:
                config = SystemConfig(**config_data)
                db.session.add(config)

        db.session.commit()
        click.echo("✓ System configuration created")

        click.echo("\n" + "="*50)
        click.echo("Database initialization complete!")
        click.echo("="*50)
        click.echo("\nNext steps:")
        click.echo("1. Start the API server:")
        click.echo("   docker-compose up -d")
        click.echo("\n2. Login with admin credentials:")
        click.echo(f"   curl -X POST http://localhost:8000/api/v1/auth/login \\")
        click.echo(f"     -d '{{\"username\":\"{admin_username}\",\"password\":\"YOUR_PASSWORD\"}}'")
        click.echo("\n3. Check the API documentation:")
        click.echo("   See docs/API.md")


if __name__ == '__main__':
    init_database()
