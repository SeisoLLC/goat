# GOAT Development Notes

## Environment Setup

Ensure you have `docker` and `pipenv` installed locally, and the `docker` daemon is running. Then run the following command to install the dependencies onto
your local system:

```bash
task init
```

We are also in the process of migrating from `Invoke` to `Taskfile`; if you want to use the `task` commands, you must install `Taskfile`

### Helpful tasks

Build all of the supported Docker images:

```bash
PLATFORM='all' task build
```

To build a Docker image for a specific platform, set `PLATFORM` to either `linux/arm64` or `linux/amd64`. In order for this to work, you must have QEMU or a
similar emulation package setup (which is usually there by default); this is why we use `docker/setup-qemu-action@v3` in the GitHub Actions pipeline.

## Running the goat against the goat project locally

There are two ways of running the `goat` locally:

1. To see how it will look in a pipeline:

    ```bash
    task test
    ```

    Or run `task test -- debug` to run it in debug mode.

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

5. The goat features AI code reviews on pull requests by leveraging OpenAI's ChatGPT API. To perform an AI augmented code review, follow these steps:
   1. Export a GH PAT for access to the GH API: `export GITHUB_TOKEN='<GitHub Personal Access Token>'`
   2. Export an open pull request: `export GITHUB_REF=goat/pull/178`
   3. Export the repository name: `export GITHUB_REPOSITORY=seisollc/goat`
   4. Export a variable to simulate a GitHub Action locally: `export GITHUB_ACTIONS=true`
   5. Export an OpenAI API key: `export OPENAI_API_KEY='<OpenAI API Key>'`
   6. Run the goat against your code:

   ```bash
    docker run --rm --env OPENAI_API_KEY=$OPENAI_API_KEY --env GITHUB_TOKEN=$GITHUB_TOKEN --env 
    GITHUB_REF=$GITHUB_REF --env GITHUB_REPOSITORY=$GITHUB_REPOSITORY --env GITHUB_ACTIONS=$GITHUB_ACTIONS -v ".:/goat/" seiso/goat:latest
   ```

Optional: To disable the code reviews, set `INPUT_DISABLE_CODE_REVIEW=true`

### Linter Update Considerations

1. If adding linters to `linters.json`, the `executor` is an optional member of the linter object.
2. The `autofix` member is also optional. If a linter has an autofix command-line option, this field holds those arguments.

## Common Errors

When attempting a `PLATFORM=all task build` you may encounter this error:

```bash
ERROR: Multiple platforms feature is currently not supported for docker driver. Please switch to a different driver (eg. "docker buildx create --use")

task: Failed to run task "build": exit status 1
```

Recreating your `desktop-linux` builder instance may fix it:

```bash
docker context rm -f desktop-linux
docker buildx create --name desktop-linux --driver docker-container --use
```
