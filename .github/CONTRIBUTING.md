# GOAT Development Notes

## Environment Setup

Ensure you have `docker` and `pipenv` installed locally, and the `docker` daemon is running. Then run the following command to install the dependencies onto
your local system:

```bash
task init
```

We are also in the process of migrating from `Invoke` to `Taskfile`; if you want to use the `task` commands, you must install `Taskfile`

## Running the goat against the goat project locally

There are two ways of running the `goat` locally:

1. To see how it will look in a pipeline:

    ```bash
    task test
    ```

    Or add `--debug` for more information.

2. For speed during development, `docker` caching can be helpful:

    ```bash
    docker build .
    docker run -v $PWD:/goat/ --rm <first several character of the hash output from the build step>
    ```

3. It is possible to pass custom arguments or config file paths to the linters in the goat using environment variables (detailed in `linters.json`).
   Examples:

   `docker run -e RUFF_CONFIG='check --config <path to new config> -v' --rm <hash>`

    ```bash
    docker run -e INPUT_EXCLUDE='.*\.json$' -e BLACK_CONFIG='--required-version 21.9b0' -v $PWD:/goat/ --rm <hash>

    Running Seiso Linter
    --------------------------

    Running linter: ruff
    Running linter: hadolint
    Running linter: kubeconform
    Running linter: dockerfile_lint
    Running linter: markdown-link-check
    Running linter: cspell
    Running linter: cfn-lint
    Running linter: jscpd
    Running linter: actionlint
    Running linter: markdownlint
    Running linter: textlint
    Running linter: black
    Running linter: mypy
    Running linter: shellcheck
    Running linter: yamllint
    ===============================
    BLACK
    -------------------------------
    Oh no! 💥 💔 💥 The required version `21.9b0` does not match the running version `23.3.0`!

    Scanned 45 files in 6 seconds
    Excluded 575 files

    INFO:  hadolint completed successfully
    INFO:  dockerfile_lint completed successfully
    INFO:  cfn-lint completed successfully
    INFO:  textlint completed successfully
    INFO:  markdownlint completed successfully
    INFO:  mypy completed successfully
    INFO:  jscpd completed successfully
    INFO:  kubeconform completed successfully
    INFO:  shellcheck completed successfully
    INFO:  ruff completed successfully
    INFO:  cspell completed successfully
    INFO:  actionlint completed successfully
    INFO:  markdown-link-check completed successfully
    INFO:  yamllint completed successfully
    ERROR:  black found errors
    ERROR:  Linting failed
    ```

    Note: Linter env variables must be formatted as <LINTER_CONFIG>, i.e. RUFF_CONFIG, CFN_LINT_CONFIG, etc.,
    and the values supplied will take precedence over the default autofix or standard arguments supplied in the goat.
    Any desired autofix arguments must be explicitly supplied as part of the new env variable value.

4. Autofix is available for certain linters and is enabled by default. To disable autofix, use one of these approaches:
   1. `docker run -e INPUT_AUTO_FIX="false" -v "$PWD:/goat/" --rm <hash>` or
   2. `INPUT_AUTO_FIX=false task test`

### Linter Update Considerations

1. If adding linters to `linters.json`, the `executor` is an optional member of the linter object.
2. The `autofix` member is also optional. If a linter has an autofix command-line option, this field holds those arguments.