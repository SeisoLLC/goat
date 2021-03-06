# Grand Opinionated AutoTester (GOAT)

The Grand Opinionated AutoTester (GOAT) automatically applies Seiso's standard
testing.

## Getting Started

1. Create a per-repository dictionary (relative to the root of your git repo).

    ```bash
    mkdir -p .github/etc/
    touch .github/etc/dictionary.txt
    ```

1. Ensure your code is checked out during the github action.

    ```bash
    uses: actions/checkout@v2
    ```

1. Add the goat to your GitHub Actions workflows.

    ```bash
    uses: seisollc/goat@main
    ```

### Example

To run the goat on each PR against `main`, create the following file as
`.github/workflows/pr.yml`:

For example, you could use the following to run the goat on each PR against
`main`:

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

1. Populate the custom dictionary file in `.github/etc/dictionary.txt` for any
   repo-specific language.

    ```bash
    $ cat << EOF >> .github/etc/dictionary.txt
    capricornis
    crispus
    EOF
    ```

1. Configure the goat to skip terrascan scanning.

    ```bash
    uses: seisollc/goat@main
    with:
      disable_terrascan: true
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

1. Provide a linting configuration for any of the linters `super-linter` uses.

    ```bash
    $ mkdir -p .github/linters/
    $ cat << EOF >> .github/linters/.markdown-lint.yml
    ---
    MD013:
      line_length: 120
    EOF
    ```

## Releases

The `goat` project does not do releases, as it is intended as a minimum
expectation that evolves over time. Please refer to `main` or, in limited
situations, pin to the commit hash tag that is published with each commit.

## GOAT Development

### Prerequisites

```bash
pipenv
```

### Running the goat locally

```bash
pipenv install --dev
pipenv run invoke goat
```
