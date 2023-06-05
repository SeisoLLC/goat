# Grand Opinionated AutoTester (GOAT)

The Grand Opinionated AutoTester (GOAT) automatically applies Seiso's standard testing.
This project has been designed to be easier to understand and more opinionated than other open source multi-linter projects.

## Getting Started

1. Create a per-repository dictionary (relative to the root of your git repository).

    ```bash
    mkdir -p .github/etc/
    touch .github/etc/dictionary.txt
    ```

1. Ensure your code is checked out during the GitHub action.

    ```bash
    uses: actions/checkout@v2
    ```

1. Add the goat to your GitHub Actions workflows.

    ```bash
    uses: seisollc/goat@main
    ```

### Example

To run the goat on each PR against `main`, create the following file as `.github/workflows/pr.yml`:

For example, you could use the following to run the goat on each PR against `main`:

```yml
---
on:
  pull_request:
    branches:
      - main
jobs:
  test:
    runs-on: Ubuntu-20.04
    name: Test the project
    steps:
    - uses: actions/checkout@v2
    - uses: seisollc/goat@main
```

#### Customizations

1. Populate the custom dictionary file in `.github/etc/dictionary.txt` for any repository-specific language.

    ```bash
    $ cat << EOF >> .github/etc/dictionary.txt
    capricornis
    crispus
    EOF
    ```

1. Configure the goat to skip mypy scanning.

    ```bash
    uses: seisollc/goat@main
    with:
      disable_mypy: true
    ```

1. Exclude a file extension.

    ```bash
    uses: seisollc/goat@main
    with:
      exclude: \.md$
    ```

1. Exclude a list of files.

    ```bash
    uses: seisollc/goat@main
    with:
      exclude: ^.*/(Dockerfile|Dockerfile\.dev)$
    ```

1. Provide a linting configuration for any of the supported linters in the `.github/linters/` directory of your repository.

    ```bash
    $ mkdir -p .github/linters/
    $ cat << EOF >> .github/linters/.markdown-lint.yml
    ---
    MD013:
      line_length: 120
    EOF
    ```
  
1. Autofix code formatting errors using those linters with a built-in `fix` option. Note, this will create a `dirty` git directory,  
   and you will need to manage committing and pushing any changes; consider setting `INPUT_AUTO_FIX=true` locally instead.

    ```bash
    uses: seisollc/goat@main
    with:
      auto_fix: true
    ```

#### Supported Linters

- actionlint
- black
- cfn-lint
- cspell
- dockerfile_lint
- hadolint
- jscpd
- kubeconform
- markdown-link-check
- markdownlint
- mypy
- ruff
- shellcheck
- textlint
- yamllint

#### Debugging

To debug an issue with the goat, configure the log level to either `ERROR`, `WARN`, `NOTICE`, `VERBOSE`, `DEBUG`, or `TRACE`.

```bash
uses: seisollc/goat@main
with:
  log_level: DEBUG
```

## Releases

The `goat` project does not do releases, as it is intended as a minimum expectation that evolves over time. Please refer to `main` or, in limited
situations, pin to the commit hash tag that is published with each commit.

## GOAT Development

See [CONTRIBUTING.md](./CONTRIBUTING.md)
