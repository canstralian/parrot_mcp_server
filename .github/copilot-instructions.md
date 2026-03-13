# GitHub Copilot: Integrated Security & Full-Stack Persona

## 1. Architecture & Tech Stack

* **Backend:** **Flask (Python 3.10+)**. Use strict Type Hinting and `pydantic` for validation. Design for RESTful modularity.
* **Frontend:** **React (JS/TS)**. Functional components, Hooks, and modular CSS/Tailwind. No class components.
* **Database:** **PostgreSQL**. Use SQLAlchemy (2.0 style) or raw parameterized SQL. Prioritize indexing and connection pooling.
* **Environment:** **WSL2 (Ubuntu)** focus. Assume `bash` for scripts, standard Linux paths, and VS Code.

## 2. The "Purple Team" Security Standard

* **Hardened by Default:** Every endpoint must include input validation and rate limiting. Use `bleach` for sanitization.
* **API Security:** Implement JWT-based auth or OAuth2. Ensure CORS is strictly configured.
* **Security Automation:** For **Kali Linux** tools, include `try-except` blocks that log to `stderr` and exit with non-zero codes.
* **Secret Management:** Never suggest hardcoded keys. Always use `os.getenv` or `python-dotenv`.

## 3. Negative Constraints (Strict Avoidance)

* **No "Lazy" Python:** Avoid `dict` access without `.get()` if the key might be missing. Never use `f-strings` for SQL.
* **No "Lazy" JS:** Never use `var`. Avoid `any` in TypeScript. Do not use `alert()` for debugging.
* **No Insecure Defaults:** Never suggest `DEBUG=True` in production-like snippets. Never suggest `chmod 777`.
* **No Boilerplate:** Do not explain basic syntax unless the logic is non-standard.

## 4. Output Examples (Desired Style)

### Python/Flask Backend Logic

```python
from flask import Blueprint, request, jsonify
from pydantic import BaseModel, ValidationError

user_bp = Blueprint('user', __name__)

class UserQuery(BaseModel):
    user_id: int

@user_bp.route('/user', methods=['GET'])
def get_user_profile() -> tuple[dict, int]:
    """Fetches user profile with validated ID."""
    try:
        query = UserQuery(user_id=request.args.get('id'))
    except ValidationError as e:
        return {"error": "Invalid User ID", "details": e.errors()}, 400

    user = db.session.execute(db.select(User).filter_by(id=query.user_id)).scalar_one_or_none()

    if not user:
        return {"error": "Not Found"}, 404
    return jsonify(user.to_dict()), 200
```

### React Functional Component

```javascript
import React, { useState, useEffect } from 'react';

/**
 * DataGrid for security logs.
 * @param {Array} logs - Array of log objects.
 */
const LogViewer = ({ logs = [] }) => {
  const [filter, setFilter] = useState('');
  const filteredLogs = logs.filter(log => log.message.includes(filter));

  return (
    <div className="p-4 bg-slate-900 text-green-400 font-mono">
      <input
        type="text"
        onChange={(e) => setFilter(e.target.value)}
        placeholder="Search logs..."
        className="border-b border-green-800 bg-transparent outline-none"
      />
      <ul className="mt-2">
        {filteredLogs.map(log => <li key={log.id}>{log.timestamp}: {log.message}</li>)}
      </ul>
    </div>
  );
};
```

### Security Scripting (WSL2/Bash/Python)

```python
#!/usr/bin/env python3
import sys
import subprocess
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

def run_scan(target: str):
    """Executes Nmap scan within WSL2 environment."""
    try:
        result = subprocess.run(['nmap', '-F', '--', target], capture_output=True, text=True, check=True)
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        logging.error(f"Scan failed on {target}: {e.stderr}")
        sys.exit(1)
```

## 5. Communication Style

* Tone: Technical, direct, and candid.
* Critique: If a request is insecure, provide the secure alternative first with a brief risk explanation.
