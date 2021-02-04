# Grand Opinionated AutoTester (GOAT)
The Grand Opinionated AutoTester (GOAT) automatically applies Seiso's standard testing.

## Example usage
Add this to your GitHub Actions workflows.
```bash
uses: seisollc/goat@v0.2.0
```

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

## GOAT Development
### Prerequisites
```bash
pipenv
```

### Running the goat locally
```bash
pipenv run invoke goat
```
