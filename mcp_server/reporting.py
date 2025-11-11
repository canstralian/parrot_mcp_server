"""
Advanced reporting and export functionality for scan results.

Supports multiple output formats:
- JSON: Structured data export
- CSV: Tabular data for analysis
- PDF: Professional reports with charts
- HTML: Interactive web reports
"""

import os
import json
import csv
import io
from datetime import datetime
from typing import Dict, List, Optional
import logging

from reportlab.lib.pagesizes import letter, A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.lib.enums import TA_CENTER, TA_LEFT

from mcp_server.db import ScanResult, ScanReport, db

logger = logging.getLogger(__name__)


class ReportGenerator:
    """Generate reports in various formats"""

    def __init__(self, output_dir: str = "./reports"):
        """
        Initialize report generator.

        Args:
            output_dir: Directory to store generated reports
        """
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)

    def generate_report(
        self,
        scan: ScanResult,
        format: str = "json",
        include_raw: bool = False
    ) -> Dict:
        """
        Generate a report in the specified format.

        Args:
            scan: ScanResult object
            format: Report format (json, csv, pdf, html)
            include_raw: Include raw Nmap output

        Returns:
            Dict with file_path and metadata
        """
        if format == "json":
            return self._generate_json_report(scan, include_raw)
        elif format == "csv":
            return self._generate_csv_report(scan)
        elif format == "pdf":
            return self._generate_pdf_report(scan)
        elif format == "html":
            return self._generate_html_report(scan)
        else:
            raise ValueError(f"Unsupported format: {format}")

    def _generate_json_report(self, scan: ScanResult, include_raw: bool = False) -> Dict:
        """Generate JSON report"""
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        filename = f"scan_{scan.id}_{timestamp}.json"
        filepath = os.path.join(self.output_dir, filename)

        report_data = scan.to_dict(include_results=True)

        if not include_raw:
            report_data.pop("raw_output", None)

        # Add metadata
        report_data["report_metadata"] = {
            "generated_at": datetime.utcnow().isoformat(),
            "format": "json",
            "version": "1.0"
        }

        with open(filepath, "w") as f:
            json.dump(report_data, f, indent=2)

        file_size = os.path.getsize(filepath)

        # Save to database
        report_record = ScanReport(
            scan_id=scan.id,
            format="json",
            file_path=filepath,
            file_size_bytes=file_size
        )
        db.session.add(report_record)
        db.session.commit()

        logger.info(f"Generated JSON report: {filepath}")

        return {
            "report_id": report_record.id,
            "file_path": filepath,
            "file_size": file_size,
            "format": "json"
        }

    def _generate_csv_report(self, scan: ScanResult) -> Dict:
        """Generate CSV report with host and port data"""
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        filename = f"scan_{scan.id}_{timestamp}.csv"
        filepath = os.path.join(self.output_dir, filename)

        # Parse results
        parsed_results = json.loads(scan.parsed_results) if scan.parsed_results else {}
        hosts = parsed_results.get("hosts", [])

        with open(filepath, "w", newline="") as csvfile:
            # Write scan metadata
            writer = csv.writer(csvfile)
            writer.writerow(["# Scan Report"])
            writer.writerow(["Scan ID", scan.id])
            writer.writerow(["Target", scan.target])
            writer.writerow(["Scan Type", scan.scan_type])
            writer.writerow(["Status", scan.status])
            writer.writerow(["Started", scan.started_at])
            writer.writerow(["Completed", scan.completed_at])
            writer.writerow(["Duration (seconds)", scan.duration_seconds])
            writer.writerow([])

            # Write host and port data
            writer.writerow([
                "Host IP",
                "Status",
                "Hostname",
                "Port",
                "Protocol",
                "State",
                "Service",
                "Product",
                "Version"
            ])

            for host in hosts:
                ip = host.get("addresses", [{}])[0].get("addr", "N/A")
                status = host.get("status", "N/A")
                hostname = host.get("hostnames", [{}])[0].get("name", "N/A") if host.get("hostnames") else "N/A"

                if host.get("ports"):
                    for port in host["ports"]:
                        service = port.get("service", {})
                        writer.writerow([
                            ip,
                            status,
                            hostname,
                            port.get("portid", "N/A"),
                            port.get("protocol", "N/A"),
                            port.get("state", "N/A"),
                            service.get("name", "N/A"),
                            service.get("product", "N/A"),
                            service.get("version", "N/A")
                        ])
                else:
                    # Host with no ports found
                    writer.writerow([ip, status, hostname, "N/A", "N/A", "N/A", "N/A", "N/A", "N/A"])

        file_size = os.path.getsize(filepath)

        # Save to database
        report_record = ScanReport(
            scan_id=scan.id,
            format="csv",
            file_path=filepath,
            file_size_bytes=file_size
        )
        db.session.add(report_record)
        db.session.commit()

        logger.info(f"Generated CSV report: {filepath}")

        return {
            "report_id": report_record.id,
            "file_path": filepath,
            "file_size": file_size,
            "format": "csv"
        }

    def _generate_pdf_report(self, scan: ScanResult) -> Dict:
        """Generate professional PDF report"""
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        filename = f"scan_{scan.id}_{timestamp}.pdf"
        filepath = os.path.join(self.output_dir, filename)

        # Create PDF
        doc = SimpleDocTemplate(filepath, pagesize=letter)
        story = []
        styles = getSampleStyleSheet()

        # Custom styles
        title_style = ParagraphStyle(
            'CustomTitle',
            parent=styles['Heading1'],
            fontSize=24,
            textColor=colors.HexColor('#2C3E50'),
            spaceAfter=30,
            alignment=TA_CENTER
        )

        heading_style = ParagraphStyle(
            'CustomHeading',
            parent=styles['Heading2'],
            fontSize=16,
            textColor=colors.HexColor('#34495E'),
            spaceAfter=12
        )

        # Title
        story.append(Paragraph("Network Scan Report", title_style))
        story.append(Spacer(1, 0.2 * inch))

        # Scan Information
        story.append(Paragraph("Scan Information", heading_style))

        scan_info_data = [
            ["Scan ID:", str(scan.id)],
            ["Target:", scan.target],
            ["Scan Type:", scan.scan_type.upper()],
            ["Status:", scan.status.upper()],
            ["Started:", scan.started_at.strftime("%Y-%m-%d %H:%M:%S UTC") if scan.started_at else "N/A"],
            ["Completed:", scan.completed_at.strftime("%Y-%m-%d %H:%M:%S UTC") if scan.completed_at else "N/A"],
            ["Duration:", f"{scan.duration_seconds:.2f} seconds" if scan.duration_seconds else "N/A"],
            ["Hosts Up:", str(scan.hosts_up)],
            ["Ports Found:", str(scan.ports_found)],
        ]

        info_table = Table(scan_info_data, colWidths=[2 * inch, 4 * inch])
        info_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#ECF0F1')),
            ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, -1), 10),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('GRID', (0, 0), (-1, -1), 1, colors.HexColor('#BDC3C7'))
        ]))

        story.append(info_table)
        story.append(Spacer(1, 0.3 * inch))

        # Parse results for detailed table
        parsed_results = json.loads(scan.parsed_results) if scan.parsed_results else {}
        hosts = parsed_results.get("hosts", [])

        if hosts:
            story.append(Paragraph("Discovered Hosts and Ports", heading_style))

            for host in hosts:
                ip = host.get("addresses", [{}])[0].get("addr", "N/A")
                status = host.get("status", "N/A")

                story.append(Paragraph(f"<b>Host:</b> {ip} ({status})", styles['Normal']))

                if host.get("ports"):
                    port_data = [["Port", "Protocol", "State", "Service", "Version"]]

                    for port in host["ports"]:
                        service = port.get("service", {})
                        port_data.append([
                            str(port.get("portid", "N/A")),
                            port.get("protocol", "N/A"),
                            port.get("state", "N/A"),
                            service.get("name", "N/A"),
                            f"{service.get('product', '')} {service.get('version', '')}".strip() or "N/A"
                        ])

                    port_table = Table(port_data, colWidths=[0.8 * inch, 1 * inch, 0.8 * inch, 1.5 * inch, 2 * inch])
                    port_table.setStyle(TableStyle([
                        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#3498DB')),
                        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                        ('FONTSIZE', (0, 0), (-1, 0), 10),
                        ('BOTTOMPADDING', (0, 0), (-1, 0), 8),
                        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
                        ('GRID', (0, 0), (-1, -1), 1, colors.black)
                    ]))

                    story.append(port_table)
                else:
                    story.append(Paragraph("No open ports found", styles['Italic']))

                story.append(Spacer(1, 0.2 * inch))

        # Build PDF
        doc.build(story)

        file_size = os.path.getsize(filepath)

        # Save to database
        report_record = ScanReport(
            scan_id=scan.id,
            format="pdf",
            file_path=filepath,
            file_size_bytes=file_size
        )
        db.session.add(report_record)
        db.session.commit()

        logger.info(f"Generated PDF report: {filepath}")

        return {
            "report_id": report_record.id,
            "file_path": filepath,
            "file_size": file_size,
            "format": "pdf"
        }

    def _generate_html_report(self, scan: ScanResult) -> Dict:
        """Generate interactive HTML report"""
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        filename = f"scan_{scan.id}_{timestamp}.html"
        filepath = os.path.join(self.output_dir, filename)

        # Parse results
        parsed_results = json.loads(scan.parsed_results) if scan.parsed_results else {}
        hosts = parsed_results.get("hosts", [])

        html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scan Report - {scan.id}</title>
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }}
        h1 {{
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }}
        h2 {{
            color: #34495e;
            margin-top: 30px;
        }}
        .info-grid {{
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 15px;
            margin: 20px 0;
        }}
        .info-item {{
            background-color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
        }}
        .info-label {{
            font-weight: bold;
            color: #7f8c8d;
            font-size: 12px;
            text-transform: uppercase;
        }}
        .info-value {{
            font-size: 18px;
            color: #2c3e50;
            margin-top: 5px;
        }}
        .host-card {{
            border: 1px solid #bdc3c7;
            border-radius: 5px;
            padding: 20px;
            margin: 20px 0;
            background-color: #fff;
        }}
        .host-header {{
            font-size: 20px;
            font-weight: bold;
            color: #2980b9;
            margin-bottom: 15px;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }}
        th {{
            background-color: #3498db;
            color: white;
            padding: 12px;
            text-align: left;
        }}
        td {{
            padding: 10px;
            border-bottom: 1px solid #ecf0f1;
        }}
        tr:hover {{
            background-color: #f8f9fa;
        }}
        .status-badge {{
            display: inline-block;
            padding: 5px 10px;
            border-radius: 3px;
            font-size: 12px;
            font-weight: bold;
        }}
        .status-up {{
            background-color: #2ecc71;
            color: white;
        }}
        .status-down {{
            background-color: #e74c3c;
            color: white;
        }}
        .port-open {{
            color: #27ae60;
            font-weight: bold;
        }}
        .port-closed {{
            color: #e74c3c;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Network Scan Report</h1>

        <h2>Scan Information</h2>
        <div class="info-grid">
            <div class="info-item">
                <div class="info-label">Scan ID</div>
                <div class="info-value">{scan.id}</div>
            </div>
            <div class="info-item">
                <div class="info-label">Target</div>
                <div class="info-value">{scan.target}</div>
            </div>
            <div class="info-item">
                <div class="info-label">Scan Type</div>
                <div class="info-value">{scan.scan_type.upper()}</div>
            </div>
            <div class="info-item">
                <div class="info-label">Status</div>
                <div class="info-value">
                    <span class="status-badge status-up">{scan.status.upper()}</span>
                </div>
            </div>
            <div class="info-item">
                <div class="info-label">Duration</div>
                <div class="info-value">{scan.duration_seconds:.2f} seconds</div>
            </div>
            <div class="info-item">
                <div class="info-label">Hosts Up</div>
                <div class="info-value">{scan.hosts_up}</div>
            </div>
        </div>

        <h2>Discovered Hosts</h2>
"""

        for host in hosts:
            ip = host.get("addresses", [{}])[0].get("addr", "N/A")
            status = host.get("status", "unknown")
            hostname = host.get("hostnames", [{}])[0].get("name", "No hostname") if host.get("hostnames") else "No hostname"

            html_content += f"""
        <div class="host-card">
            <div class="host-header">
                {ip} <span class="status-badge status-{status}">{status.upper()}</span>
            </div>
            <p><strong>Hostname:</strong> {hostname}</p>
"""

            if host.get("ports"):
                html_content += """
            <table>
                <thead>
                    <tr>
                        <th>Port</th>
                        <th>Protocol</th>
                        <th>State</th>
                        <th>Service</th>
                        <th>Version</th>
                    </tr>
                </thead>
                <tbody>
"""

                for port in host["ports"]:
                    service = port.get("service", {})
                    port_state = port.get("state", "unknown")
                    state_class = "port-open" if port_state == "open" else "port-closed"

                    version = f"{service.get('product', '')} {service.get('version', '')}".strip() or "N/A"

                    html_content += f"""
                    <tr>
                        <td>{port.get('portid', 'N/A')}</td>
                        <td>{port.get('protocol', 'N/A')}</td>
                        <td class="{state_class}">{port_state.upper()}</td>
                        <td>{service.get('name', 'N/A')}</td>
                        <td>{version}</td>
                    </tr>
"""

                html_content += """
                </tbody>
            </table>
"""
            else:
                html_content += "<p><em>No open ports found</em></p>"

            html_content += "</div>"

        html_content += """
    </div>
</body>
</html>
"""

        with open(filepath, "w") as f:
            f.write(html_content)

        file_size = os.path.getsize(filepath)

        # Save to database
        report_record = ScanReport(
            scan_id=scan.id,
            format="html",
            file_path=filepath,
            file_size_bytes=file_size
        )
        db.session.add(report_record)
        db.session.commit()

        logger.info(f"Generated HTML report: {filepath}")

        return {
            "report_id": report_record.id,
            "file_path": filepath,
            "file_size": file_size,
            "format": "html"
        }


def generate_scan_report(scan_id: int, format: str = "json", include_raw: bool = False) -> Dict:
    """
    Convenience function to generate a report for a scan.

    Args:
        scan_id: Scan ID
        format: Report format
        include_raw: Include raw output (JSON only)

    Returns:
        Dict with report information
    """
    scan = ScanResult.query.get(scan_id)
    if not scan:
        raise ValueError(f"Scan {scan_id} not found")

    generator = ReportGenerator()
    return generator.generate_report(scan, format, include_raw)
