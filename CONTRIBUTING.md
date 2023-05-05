# GOAT Development Notes

## Environmental Setup

Ensure you have `docker` and `pipenv` installed locally, and the `docker` daemon is running.  
Then run the following command to install the dependencies onto your local system:  

```bash
pipenv install --deploy --ignore-pipfile --dev 
```

## Running the goat against the goat project locally

There are two ways of running the `goat` locally:

1. To see how it will look in a pipeline:

    ```bash
    pipenv run invoke goat
    ```

    Or add `--debug` for more information.

2. For speed during development, `docker` caching can be helpful:

    ```bash
    docker build .
    docker run -e RUN_LOCAL=true -it -v $PWD:/goat/ --rm <first several character of the hash output from the build step>
    ```

### Note

If adding linters to `linters.json`, the `executor` is an optional member of the linter object.
