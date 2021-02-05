# Grand Opinionated AutoTester (GOAT)
The Grand Opinionated AutoTester (GOAT) automatically applies Seiso's standard testing.

## Getting Started
1. Create a dictionary text file in `.github/etc/dictionary.txt` (relative to the root of your git repo).
1. Add the goat to your GitHub Actions workflows.
```bash
uses: seisollc/goat@v0.2.0
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
    - uses: seisollc/goat@v0.2.0
```

and then store a custom dictionary file in `.github/etc/dictionary.txt` that accounts for your repo-specific language.  For example:
```bash
$ cat << EOF >> .github/etc/dictionary.txt
capricornis
crispus
EOF
```

## GOAT Development
### Prerequisites
```bash
pipenv
```

### Running the goat locally
```bash
pipenv run invoke goat
```
