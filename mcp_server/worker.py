"""
Celery worker for asynchronous Nmap scan execution.

This module implements task queue management using Celery and Redis,
enabling scalable, distributed scanning capabilities.
"""

import os
import logging
import json
from datetime import datetime
from celery import Celery, Task
from celery.signals import task_prerun, task_postrun, task_failure
from typing import Dict, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Celery configuration
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
BROKER_URL = os.getenv("CELERY_BROKER_URL", REDIS_URL)
RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", REDIS_URL)

# Initialize Celery app
celery_app = Celery(
    "parrot_nmap_worker",
    broker=BROKER_URL,
    backend=RESULT_BACKEND
)

# Celery configuration
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=3600,  # 1 hour hard limit
    task_soft_time_limit=1800,  # 30 minute soft limit
    worker_prefetch_multiplier=1,  # Process one task at a time
    worker_max_tasks_per_child=50,  # Restart worker after 50 tasks (prevent memory leaks)
    task_acks_late=True,  # Acknowledge task after completion
    task_reject_on_worker_lost=True,
    result_expires=3600 * 24,  # Results expire after 24 hours
)


class DatabaseTask(Task):
    """Base task class that provides database session management"""
    _db = None

    @property
    def db(self):
        """Lazy database connection"""
        if self._db is None:
            # Import here to avoid circular imports
            from flask import Flask
            from mcp_server.db import db as database
            from mcp_server.config import Config

            app = Flask(__name__)
            app.config.from_object(Config)
            database.init_app(app)

            self._db = database
            self._app = app

        return self._db

    def get_app_context(self):
        """Get Flask application context"""
        return self._app.app_context()


@celery_app.task(bind=True, base=DatabaseTask, name="parrot.scan.execute")
def execute_scan_task(
    self,
    scan_id: int,
    target: str,
    scan_type: str,
    custom_args: Optional[str] = None
) -> Dict:
    """
    Celery task to execute an Nmap scan asynchronously.

    Args:
        self: Task instance (bound)
        scan_id: Database ID of the scan record
        target: Target IP or CIDR range
        scan_type: Type of scan to perform
        custom_args: Optional custom Nmap arguments

    Returns:
        Dict containing scan results
    """
    from mcp_server.tools import run_nmap_scan
    from mcp_server.db import ScanResult, ScanStatus

    logger.info(f"Starting scan task for scan_id={scan_id}, target={target}, type={scan_type}")

    with self.get_app_context():
        # Get scan record
        scan = ScanResult.query.get(scan_id)
        if not scan:
            logger.error(f"Scan {scan_id} not found in database")
            return {"success": False, "error": "Scan record not found"}

        try:
            # Update status to RUNNING
            scan.update_status(ScanStatus.RUNNING.value)
            scan.task_id = self.request.id
            self.db.session.commit()

            # Execute the scan
            logger.info(f"Executing Nmap scan: {target}")
            result = run_nmap_scan(target, scan_type, custom_args)

            if result.get("success"):
                # Update scan with results
                scan.raw_output = result.get("raw_output", "")
                scan.parsed_results = json.dumps(result.get("parsed_results", {}))
                scan.duration_seconds = result.get("duration_seconds", 0)

                # Extract statistics
                parsed = result.get("parsed_results", {})
                if isinstance(parsed, dict):
                    stats = parsed.get("stats", {})
                    scan.hosts_up = stats.get("hosts_up", 0)
                    scan.ports_found = stats.get("total_ports", 0)

                    # Count vulnerabilities if vuln scan
                    if scan_type == "vuln":
                        vuln_count = 0
                        for host in parsed.get("hosts", []):
                            for port in host.get("ports", []):
                                service = port.get("service", {})
                                # Simple heuristic: count services with known issues
                                if service.get("extrainfo"):
                                    vuln_count += 1
                        scan.vulnerabilities_found = vuln_count

                scan.update_status(ScanStatus.COMPLETED.value)
                logger.info(f"Scan {scan_id} completed successfully")

                return {
                    "success": True,
                    "scan_id": scan_id,
                    "hosts_up": scan.hosts_up,
                    "ports_found": scan.ports_found
                }

            else:
                # Scan failed
                error_msg = result.get("error", "Unknown error")
                scan.update_status(ScanStatus.FAILED.value, error_message=error_msg)
                logger.error(f"Scan {scan_id} failed: {error_msg}")

                return {
                    "success": False,
                    "scan_id": scan_id,
                    "error": error_msg
                }

        except Exception as e:
            logger.exception(f"Unexpected error in scan task {scan_id}")
            scan.update_status(
                ScanStatus.FAILED.value,
                error_message=f"Task execution error: {str(e)}"
            )
            return {
                "success": False,
                "scan_id": scan_id,
                "error": str(e)
            }


@celery_app.task(bind=True, name="parrot.scan.bulk_execute")
def bulk_scan_task(self, scan_ids: list) -> Dict:
    """
    Execute multiple scans in sequence.

    Args:
        self: Task instance
        scan_ids: List of scan IDs to execute

    Returns:
        Dict with results summary
    """
    logger.info(f"Starting bulk scan for {len(scan_ids)} scans")

    results = {
        "total": len(scan_ids),
        "completed": 0,
        "failed": 0,
        "scans": []
    }

    for scan_id in scan_ids:
        from mcp_server.db import ScanResult

        with self.get_app_context():
            scan = ScanResult.query.get(scan_id)
            if not scan:
                logger.warning(f"Scan {scan_id} not found, skipping")
                results["failed"] += 1
                continue

            # Queue individual scan task
            task = execute_scan_task.apply_async(
                args=[scan_id, scan.target, scan.scan_type, scan.scan_args]
            )

            results["scans"].append({
                "scan_id": scan_id,
                "task_id": task.id,
                "target": scan.target
            })

    logger.info(f"Bulk scan queued {len(results['scans'])} tasks")
    return results


@celery_app.task(name="parrot.scan.cleanup_old_results")
def cleanup_old_results_task(days: int = 30) -> Dict:
    """
    Cleanup old scan results from database.

    Args:
        days: Delete scans older than this many days

    Returns:
        Dict with cleanup statistics
    """
    from datetime import timedelta
    from mcp_server.db import ScanResult

    logger.info(f"Starting cleanup of scans older than {days} days")

    with celery_app.db.get_app_context():
        cutoff_date = datetime.utcnow() - timedelta(days=days)

        # Find old scans
        old_scans = ScanResult.query.filter(
            ScanResult.created_at < cutoff_date
        ).all()

        deleted_count = len(old_scans)

        # Delete
        for scan in old_scans:
            celery_app.db.session.delete(scan)

        celery_app.db.session.commit()

        logger.info(f"Cleaned up {deleted_count} old scan records")

        return {
            "success": True,
            "deleted_count": deleted_count,
            "cutoff_date": cutoff_date.isoformat()
        }


@celery_app.task(name="parrot.scan.retry_failed")
def retry_failed_scans_task(max_age_hours: int = 24) -> Dict:
    """
    Retry failed scans that are not too old.

    Args:
        max_age_hours: Only retry scans failed within this many hours

    Returns:
        Dict with retry statistics
    """
    from datetime import timedelta
    from mcp_server.db import ScanResult, ScanStatus

    logger.info(f"Retrying failed scans from last {max_age_hours} hours")

    with celery_app.db.get_app_context():
        cutoff_date = datetime.utcnow() - timedelta(hours=max_age_hours)

        # Find failed scans
        failed_scans = ScanResult.query.filter(
            ScanResult.status == ScanStatus.FAILED.value,
            ScanResult.created_at >= cutoff_date
        ).all()

        retry_count = 0

        for scan in failed_scans:
            # Re-queue the scan
            task = execute_scan_task.apply_async(
                args=[scan.id, scan.target, scan.scan_type, scan.scan_args]
            )
            scan.task_id = task.id
            scan.status = ScanStatus.QUEUED.value
            scan.error_message = None
            retry_count += 1

        celery_app.db.session.commit()

        logger.info(f"Requeued {retry_count} failed scans")

        return {
            "success": True,
            "retry_count": retry_count
        }


# Signal handlers for monitoring and logging

@task_prerun.connect
def task_prerun_handler(sender=None, task_id=None, task=None, args=None, kwargs=None, **extra):
    """Log when task starts"""
    logger.info(f"Task {task.name} [{task_id}] starting")


@task_postrun.connect
def task_postrun_handler(
    sender=None, task_id=None, task=None, args=None, kwargs=None,
    retval=None, state=None, **extra
):
    """Log when task completes"""
    logger.info(f"Task {task.name} [{task_id}] completed with state: {state}")


@task_failure.connect
def task_failure_handler(
    sender=None, task_id=None, exception=None, args=None, kwargs=None,
    traceback=None, einfo=None, **extra
):
    """Log task failures"""
    logger.error(f"Task {sender.name} [{task_id}] failed: {exception}")
    logger.error(f"Traceback: {traceback}")


# Periodic tasks configuration
celery_app.conf.beat_schedule = {
    "cleanup-old-scans-daily": {
        "task": "parrot.scan.cleanup_old_results",
        "schedule": 3600 * 24,  # Daily
        "args": (30,)  # 30 days
    },
    "retry-failed-scans-hourly": {
        "task": "parrot.scan.retry_failed",
        "schedule": 3600,  # Hourly
        "args": (24,)  # Last 24 hours
    }
}


if __name__ == "__main__":
    # For development/testing
    celery_app.start()
