
# Raspberry Pi 5 Bash Script Library

This project is a robust, production-ready library of Bash scripts for Raspberry Pi 5, managed by a central CLI tool (`cli.sh`).
It includes system maintenance, automation, and developer-friendly features for reliability and ease of use.

## Usage

```sh
./cli.sh <script> [args]
```

- Lists available scripts if no argument is given.
- Runs the specified script from the `scripts/` directory.
- Run `./cli.sh` with no arguments for an interactive menu.

## Adding Scripts

1. Place your Bash script in the `scripts/` directory.
2. Name it `<name>.sh` and make it executable (`chmod +x scripts/<name>.sh`).
3. It will be automatically available via `cli.sh <name>` or from the menu.

## Example

```sh
./cli.sh hello
```

## Automated Maintenance Scheduling

To automate all recommended maintenance tasks, run:

```sh
./cli.sh setup_cron
```

This will install cron jobs for updates, cache cleaning, disk checks, backups, and log rotation. View your crontab with `crontab -l`.

You can still manually edit or add cron jobs as needed.

## Setup

- Ensure `cli.sh` is executable: `chmod +x cli.sh`
- Optionally run `make install` or `./install.sh` if provided.

## Code Quality & Automation

- All scripts are linted with [ShellCheck](https://www.shellcheck.net/) and formatted with [shfmt](https://github.com/mvdan/sh).
- To lint scripts manually:

 ```sh
 shellcheck cli.sh scripts/*.sh
 ```

- To format scripts:

 ```sh
 shfmt -w cli.sh scripts/*.sh
 ```

- Continuous Integration (CI) runs ShellCheck, shfmt, and basic script tests on every push and pull request (see `.github/workflows/ci.yml`).
- See `TESTING.md` for more details on manual and automated testing.

## Contributing & Community

- See `CONTRIBUTING.md` for guidelines.
- All contributors must follow the `CODE_OF_CONDUCT.md`.
- Use the provided issue and pull request templates for contributions.

## License

MIT
