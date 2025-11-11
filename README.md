# 🦜 Parrot MCP Server

[![CI Pipeline](https://github.com/canstralian/parrot_mcp_server/actions/workflows/ci.yml/badge.svg)](https://github.com/canstralian/parrot_mcp_server/actions/workflows/ci.yml)
[![Build Status](https://github.com/canstralian/parrot_mcp_server/actions/workflows/build.yml/badge.svg)](https://github.com/canstralian/parrot_mcp_server/actions/workflows/build.yml)
[![Tests](https://github.com/canstralian/parrot_mcp_server/actions/workflows/test.yml/badge.svg)](https://github.com/canstralian/parrot_mcp_server/actions/workflows/test.yml)
[![Shell Lint](https://github.com/canstralian/parrot_mcp_server/actions/workflows/lint.yml/badge.svg)](https://github.com/canstralian/parrot_mcp_server/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](./Dockerfile)
[![Kubernetes](https://img.shields.io/badge/kubernetes-ready-326CE5.svg)](./k8s)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://github.com/canstralian/parrot_mcp_server/issues)
[![Built with ❤️ by Humans and Parrots](https://img.shields.io/badge/built%20with-%E2%9D%A4%EF%B8%8F%20by%20parrots-blueviolet)](#)

**Hardware setup? See [`HARDWARE_BOM.md`](./HARDWARE_BOM.md) for a complete bill of materials and assembly checklist for the Rackmate T0 Parrot MCP Edge Node.**
A lightweight, modular, and hacker-friendly **Model Context Protocol (MCP)** server designed to make your AI integrations sing.  
Built for tinkerers, researchers, and developers who believe that communication between machines should be as elegant as parrots mimicking poetry.

---

## 🚀 What Is This?

**Parrot MCP Server** is a minimal yet extensible implementation of the **Model Context Protocol**, enabling structured message exchange between AI clients and local tools or services.  
Think of it as a translation layer that helps your AI agents "talk" to your system — whether it’s running on a Raspberry Pi, a cloud VM, or your secret lab server.

It’s built in **Shell** for portability and clarity, with simple scripts to configure, launch, and manage model-context endpoints.

---

## 🧩 Features

- **MCP-compliant core** – speaks the official Model Context Protocol fluently.  
- **Lightweight shell design** – runs anywhere Bash runs (including tiny SBCs).  
- **Modular structure** – extend with your own tools or agents.  
- **Zero dependencies** – no Python virtualenvs or Node modules needed.  
- **Docker & Kubernetes ready** – production-grade containerization and orchestration.
- **CI/CD pipeline** – automated testing, security scanning, and deployment.
- **Perfect for experimentation** – hack, fork, break, and rebuild with joy.

---

## 🛠️ Installation & Quick Start

### Local Installation

Clone and run locally:

```bash
git clone https://github.com/canstralian/parrot_mcp_server.git
cd parrot_mcp_server
chmod +x ./rpi-scripts/*.sh

# Start the server
./rpi-scripts/start_mcp_server.sh

# Run tests
./rpi-scripts/test_mcp_local.sh
```

### Docker Installation

```bash
# Using docker-compose (recommended)
docker-compose up -d

# Or build and run manually
docker build -t parrot-mcp-server .
docker run -d -p 8080:8080 --name mcp-server parrot-mcp-server
```

### Kubernetes Deployment

```bash
# Apply all Kubernetes manifests
kubectl apply -f k8s/

# Check deployment status
kubectl get pods -l app=mcp-server
```

For detailed deployment instructions, see [DEPLOYMENT.md](./DEPLOYMENT.md).

---

## 🧠 Philosophy

This project is an invitation — not a product.
Its mission is to demystify the infrastructure that connects AIs to their contexts.
In a world of opaque LLM integrations, Parrot MCP aims for clarity, transparency, and hackability.

The best way to understand a system is to build it, break it, and build it again.

---

## 🤝 Contributing

We welcome pull requests, issue reports, and wild ideas.
	1.	Fork the repo
	2.	Create a feature branch (git checkout -b feature/your-idea)
	3.	Commit changes with meaning (git commit -m "Add rainbow squawk support")
	4.	Push and open a PR

Please follow good shell practices:
	•	Use portable Bash syntax (#!/usr/bin/env bash)
	•	Comment clearly, especially for edge-case handling
	•	Keep functions small and composable

---

## 🧪 Testing

### Local Testing

```bash
# Run MCP protocol tests
./rpi-scripts/test_mcp_local.sh

# Run smoke tests
./scripts/smoke-test.sh
```

### CI/CD Pipeline

The project includes comprehensive automated testing:

- **Linting**: ShellCheck for code quality
- **Unit Tests**: MCP protocol compliance tests
- **Security**: Trivy vulnerability scanning
- **Integration Tests**: End-to-end validation
- **Smoke Tests**: Post-deployment validation

All tests run automatically on every push and pull request via GitHub Actions.

---

## 🚢 Deployment

### Production Deployment

The project includes a complete CI/CD pipeline and deployment infrastructure:

- **Automated CI**: Linting, testing, security scanning, and Docker builds
- **Staging Environment**: Auto-deploys from `develop` branch
- **Production Deployment**: Blue-green deployment with manual approval
- **Container Support**: Docker and Kubernetes ready
- **Monitoring**: Health checks and smoke tests

See [DEPLOYMENT.md](./DEPLOYMENT.md) for comprehensive deployment instructions.

### Deployment Environments

| Environment | Branch | Deployment | URL |
|-------------|--------|------------|-----|
| Development | Any | Manual | Local |
| Staging | `develop` | Automatic | staging.example.com |
| Production | Release tag | Manual approval | parrot-mcp.example.com |

---

## 🦜 Community and Collaboration

This project thrives on curiosity.
You don’t need to be a veteran developer to join — only to care about making AI tools more open, more understandable, and more fun.

Join discussions, open issues, and share insights.
If you make something weird or brilliant, please tell us — parrots love to echo brilliance.

---

## 🪶 License

Released under the MIT License.
You’re free to use, modify, and redistribute — just keep the credits intact.

---

## 🌈 Future Directions

- Add Python and Go bindings for hybrid setups
- Support for WebSocket-based AI toolchains
- Optional encryption layer for secure context exchange
- Visualization dashboard for active context sessions

---

## 🗣️ Final Words

This isn’t just a server — it’s a conversation starter between humans, code, and context.
The MCP is young, and the ecosystem needs explorers.
Let’s make open source speak louder, clearer, and stranger together.

---

"When machines talk, may they do so in the voice of a parrot — endlessly curious, delightfully weird, and never dull."

⸻



