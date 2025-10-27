# Testing Guide

## Linting and Formatting

- All scripts must pass [ShellCheck](https://www.shellcheck.net/) and be formatted with [shfmt](https://github.com/mvdan/sh).
- Run locally:

  ```sh
  shellcheck cli.sh scripts/*.sh
  shfmt -d cli.sh scripts/*.sh
  ```

## Manual Testing

- Run the CLI menu: `./cli.sh` and test all options interactively.
- Test direct script calls, e.g. `./cli.sh system_update`.
- Test cron automation: `./cli.sh setup_cron` and verify with `crontab -l`.

## Automated Testing

- [Bats](https://github.com/bats-core/bats-core) is recommended for Bash unit/integration tests.
- Example test (add to `tests/` directory):

  ```bash
  @test "hello script outputs greeting" {
    run ./cli.sh hello
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hello from Raspberry Pi 5"* ]]
  }
  ```

- To run all Bats tests:

  ```sh
  bats tests/
  ```
