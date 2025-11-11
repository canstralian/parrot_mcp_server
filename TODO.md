# TODO

This file tracks major issues and problems that need to be addressed in future releases.

## Major Issues

- [x] **Security Vulnerability:** ~~The use of `/tmp` for inter-process communication is a major security vulnerability. This needs to be replaced with a more secure method, such as named pipes or Unix domain sockets.~~ **FIXED:** Replaced `/tmp` file-based IPC with secure named pipes using umask 0077 for restrictive permissions. See `SECURITY_IMPROVEMENTS.md` for details.
- [ ] **Not a Real Server:** The current "server" is just a simulation. To be a real server, it needs to listen on a network socket and handle incoming connections. This will likely require moving away from pure shell scripts to a language with better networking support, like Python or Go.
- [ ] **Limited Functionality:** The server's functionality is very limited. It can only handle "ping" messages. More functionality needs to be added to make the server useful.

## Minor Issues

- [x] **Lack of input validation:** ~~The scripts that take input from the user or from files do not perform any input validation. This could lead to unexpected behavior or security vulnerabilities.~~ **FIXED:** Added comprehensive input validation functions for IPv4 addresses, port numbers, email addresses, paths, and general input sanitization. Both Bash and Python validation modules are now available. See `SECURITY_IMPROVEMENTS.md` for details.
