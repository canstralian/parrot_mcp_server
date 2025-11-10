# TODO

This file tracks major issues and problems that need to be addressed in future releases.

## Major Issues

- [ ] **Security Vulnerability:** The use of `/tmp` for inter-process communication is a major security vulnerability. This needs to be replaced with a more secure method, such as named pipes or Unix domain sockets.
- [ ] **Not a Real Server:** The current "server" is just a simulation. To be a real server, it needs to listen on a network socket and handle incoming connections. This will likely require moving away from pure shell scripts to a language with better networking support, like Python or Go.
- [ ] **Limited Functionality:** The server's functionality is very limited. It can only handle "ping" messages. More functionality needs to be added to make the server useful.

## Minor Issues

- [ ] **Lack of input validation:** The scripts that take input from the user or from files do not perform any input validation. This could lead to unexpected behavior or security vulnerabilities.
