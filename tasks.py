#!/usr/bin/env python3
"""
Task execution tool & library
"""

import json
import os
import re
import subprocess
import sys
from logging import basicConfig, getLogger
from pathlib import Path

import docker
import git
import requests
from invoke import task


# Helper functions
def opinionated_docker_run(
    *,
    image: str,
    command: str = "",
    volumes: dict = {},
    working_dir: str = "/goat/",
    auto_remove: bool = False,
    detach: bool = True,
    environment: dict = {},
    entrypoint: str = str(),
    expected_exit: int = 0,
):
    """Perform an opinionated docker run"""
    if entrypoint:
        container = CLIENT.containers.run(
            auto_remove=auto_remove,
            command=command,
            detach=detach,
            environment=environment,
            entrypoint=entrypoint,
            image=image,
            volumes=volumes,
            working_dir=working_dir,
        )
    else:
        container = CLIENT.containers.run(
            auto_remove=auto_remove,
            command=command,
            detach=detach,
            environment=environment,
            image=image,
            volumes=volumes,
            working_dir=working_dir,
        )

    if not auto_remove:
        response = container.wait(condition="not-running")
        decoded_response = container.logs().decode("utf-8")
        response["logs"] = decoded_response.strip().replace("\n", "  ")
        container.remove()
        if not is_status_expected(expected=expected_exit, response=response):
            sys.exit(response["StatusCode"])


def is_status_expected(*, expected: int, response: dict) -> bool:
    """Check to see if the status code was expected"""
    actual = response["StatusCode"]

    if expected != actual:
        LOG.error(
            "Received a baaaaaaaaah-d status code from docker (%s); additional details: %s",
            response["StatusCode"],
            response["logs"],
        )
        return False

    return True


def run_security_tests(*, image: str):
    """Run the security tests"""
    temp_dir = CWD

    if os.environ.get("GITHUB_ACTIONS") == "true":
        if os.environ.get("RUNNER_TEMP"):
            # Update the temp_dir if a temporary directory is indicated by the
            # environment
            temp_dir = Path(str(os.environ.get("RUNNER_TEMP"))).absolute()
        else:
            LOG.warning(
                "Unable to determine the context due to inconsistent environment variables, falling back to %s",
                str(temp_dir),
            )

    tag = image.split(":")[-1]
    file_name = tag + ".tar"
    image_file = temp_dir.joinpath(file_name)
    raw_image = CLIENT.images.get(image).save(named=True)
    with open(image_file, "wb") as file:
        for chunk in raw_image:
            file.write(chunk)

    working_dir = "/tmp/"
    volumes = {temp_dir: {"bind": working_dir, "mode": "rw"}}

    num_tests_ran = 0
    scanner = "aquasec/trivy:latest"

    # Provide information about vulnerabilities
    command = f"--quiet image --timeout 30m0s --exit-code 0 --format json --input {working_dir}{file_name}"
    opinionated_docker_run(
        image=scanner,
        command=command,
        working_dir=working_dir,
        volumes=volumes,
    )
    num_tests_ran += 1

    # Cleanup the image file
    image_file.unlink()


def get_latest_release_from_github(*, repo: str) -> str:
    """Get the latest release of a repo on github"""
    response = requests.get(
        f"https://api.github.com/repos/{repo}/releases/latest"
    ).json()
    return response["tag_name"]


def update_dockerfile_from(
    *, image: str, tag: str, file_name: str = "Dockerfile"
) -> None:
    """Update the Dockerfile"""
    file_object = Path(file_name)
    pattern = re.compile(rf"^FROM.+{image}:.+$\n")
    final_content = []

    # Validate
    if not file_object.is_file():
        LOG.error("%s is not a valid file", file_name)
        sys.exit(1)

    # Extract
    with open(file_object) as file:
        file_contents = file.readlines()

    # Transform
    for line in file_contents:
        if pattern.fullmatch(line):
            line = f"FROM {image}:slim-{tag}\n"
        final_content.append(line)

    # Load
    with open(file_object, "w") as file:
        file.writelines(final_content)


# Globals
CWD = Path(".").absolute()
NAME = "goat"
LOG_FORMAT = json.dumps(
    {
        "timestamp": "%(asctime)s",
        "namespace": "%(name)s",
        "loglevel": "%(levelname)s",
        "message": "%(message)s",
    }
)
basicConfig(level="INFO", format=LOG_FORMAT)
LOG = getLogger("seiso." + NAME)

# git
REPO = git.Repo(CWD)
COMMIT_HASH = REPO.git.rev_parse(REPO.head.commit.hexsha, short=True)

# Docker
CLIENT = docker.from_env(timeout=1200)
IMAGE = "seiso/" + NAME


# Tasks
@task
def build(_c, debug=False):
    """Build the goat"""
    if debug:
        getLogger().setLevel("DEBUG")

    buildargs = {"COMMIT_HASH": COMMIT_HASH}
    tags = [buildargs["COMMIT_HASH"], "latest"]

    for tag in tags:
        if tag == tags[0]:
            tag = IMAGE + ":" + tag
            LOG.info("Building %s...", tag)
            image = CLIENT.images.build(
                path=str(CWD), rm=True, tag=tag, buildargs=buildargs
            )[0]
        else:
            LOG.info("Tagging %s:%s...", IMAGE, tag)
            image.tag(IMAGE, tag=tag.split(":")[-1])


@task(pre=[build])
def goat(_c, disable_autofix=False, debug=False):
    """Run the goat"""
    if debug:
        getLogger().setLevel("DEBUG")

    LOG.info("Baaaaaaaaaaah! (Running the goat)")
    environment = {}
    environment["DEFAULT_WORKSPACE"] = "/goat"
    environment["INPUT_DISABLE_MYPY"] = "true"
    working_dir = "/goat/"

    if disable_autofix:
        environment["INPUT_AUTO_FIX"] = "false"
        LOG.info("Autofix has been disabled")

    if REPO.is_dirty(untracked_files=True):
        LOG.error("Linting requires a clean git directory to function properly")
        sys.exit(1)

    # Pass in all of the host environment variables starting with GITHUB_ or INPUT_
    for element in dict(os.environ):
        if element.startswith("GITHUB_"):
            environment[element] = os.environ.get(element)
        if element.startswith("INPUT_"):
            environment[element] = os.environ.get(element)

    if os.environ.get("GITHUB_ACTIONS") == "true":
        host_dir = os.environ.get("GITHUB_WORKSPACE")
        homedir = os.environ.get("HOME")
        volumes = {
            host_dir: {"bind": working_dir, "mode": "rw"},
            homedir: {"bind": homedir, "mode": "ro"},
        }
    else:
        volumes = {
            CWD: {"bind": working_dir, "mode": "rw"},
        }

    opinionated_docker_run(
        image=IMAGE,
        volumes=volumes,
        working_dir=working_dir,
        environment=environment,
    )
    LOG.info("Linting tests passed")

    latest_image = IMAGE + ":latest"
    run_security_tests(image=latest_image)
    LOG.info("Security tests passed")

    LOG.info("All goat tests completed successfully!")


@task
def publish(_c, debug=False):
    """Publish the goat"""
    if debug:
        getLogger().setLevel("DEBUG")

    for tag in [COMMIT_HASH, "latest"]:
        repository = IMAGE + ":" + tag
        LOG.info("Pushing %s to docker hub...", repository)
        CLIENT.images.push(repository=repository)
        LOG.info("Done publishing the %s Docker image", repository)


@task
def update(_c, debug=False):
    """Update the goat dependencies"""
    if debug:
        getLogger().setLevel("DEBUG")

    try:
        subprocess.run(["pipenv", "update"], capture_output=True, check=True)
    except subprocess.CalledProcessError:
        LOG.error("Unable to run pipenv update")
        sys.exit(1)
