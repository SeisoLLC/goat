#!/usr/bin/env python3
"""
Task execution tool & library
"""

import json
import os
import sys
from logging import basicConfig, getLogger
from pathlib import Path

import docker
import git
from invoke import task


# Helper functions
def opinionated_docker_run(
    *,
    image: str,
    command: str = "",
    volumes: dict = {},
    working_dir: str = "/tmp/lint/",
    auto_remove: bool = False,
    detach: bool = True,
    environment: dict = {},
    expected_exit: int = 0,
):
    """Perform an opinionated docker run"""
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
    volumes = {temp_dir: {"bind": working_dir, "mode": "ro"}}

    num_tests_ran = 0
    scanner = "aquasec/trivy:latest"

    # Provide information about low priority vulnerabilities
    command = (
        "--quiet image --exit-code 0 --severity "
        + ",".join(LOW_PRIORITY_VULNS)
        + " --format json --light --input "
        + working_dir
        + file_name
    )
    opinionated_docker_run(
        image=scanner, command=command, working_dir=working_dir, volumes=volumes,
    )
    num_tests_ran += 1

    # Ensure no unacceptable vulnerabilities exist in the image
    command = (
        "--quiet image --exit-code 1 --severity "
        + ",".join(UNACCEPTABLE_VULNS)
        + " --format json --light --input "
        + working_dir
        + file_name
    )
    opinionated_docker_run(
        image=scanner, command=command, working_dir=working_dir, volumes=volumes,
    )
    num_tests_ran += 1

    # Cleanup the image file
    image_file.unlink()


# Globals
CWD = Path(".").absolute()
VERSION = "0.4.0"
NAME = "goat"
UNACCEPTABLE_VULNS = ["CRITICAL"]
LOW_PRIORITY_VULNS = ["UNKNOWN", "LOW", "MEDIUM", "HIGH"]

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
COMMIT_HASH = REPO.head.object.hexsha

# Docker
CLIENT = docker.from_env(timeout=300)
IMAGE = "seiso/" + NAME
TAGS = [IMAGE + ":latest", IMAGE + ":" + VERSION]


# Tasks
@task
def goat(c):  # pylint: disable=unused-argument
    """Run the goat"""
    LOG.info("Baaaaaaaaaaah! (Running the goat)")
    environment = {}

    # Pass in all of the host environment variables starting with GITHUB_
    for element in dict(os.environ):
        if element.startswith("GITHUB_"):
            environment[element] = os.environ.get(element)

    if os.environ.get("GITHUB_ACTIONS") == "true":
        working_dir = os.environ.get("GITHUB_WORKSPACE")
        homedir = os.environ.get("HOME")
        volumes = {
            working_dir: {"bind": working_dir, "mode": "rw"},
            homedir: {"bind": homedir, "mode": "ro"},
        }
    else:
        environment["RUN_LOCAL"] = "true"
        working_dir = "/tmp/lint/"
        volumes = {
            CWD: {"bind": working_dir, "mode": "rw"},
        }

    opinionated_docker_run(
        image=IMAGE, volumes=volumes, working_dir=working_dir, environment=environment,
    )
    LOG.info("Linting tests passed")

    # latest_image = IMAGE + ":latest"
    # run_security_tests(image=latest_image)
    # LOG.info("Security tests passed")

    LOG.info("All goat tests completed successfully!")


@task
def build(c):  # pylint: disable=unused-argument
    """Build the goat"""
    buildargs = {"VERSION": VERSION, "COMMIT_HASH": COMMIT_HASH}

    for tag in TAGS:
        LOG.info("Building %s...", tag)
        CLIENT.images.build(path=str(CWD), rm=True, tag=tag, buildargs=buildargs)


@task
def publish(c, tag):  # pylint: disable=unused-argument
    """Publish the goat"""
    if tag not in ["latest", "version"]:
        LOG.error("Please provide a tag of either latest or version")
        sys.exit(1)
    elif tag == "version":
        tag = VERSION

    repository = IMAGE + ":" + tag
    LOG.info("Pushing %s to docker hub...", repository)
    CLIENT.images.push(repository=repository)
    LOG.info("Done publishing the %s Docker image", repository)
