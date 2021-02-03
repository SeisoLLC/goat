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

    LOG.info("The %s scan completed successfully", image)


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


# Globals
CWD = Path(".").absolute()
VERSION = "0.2.0"
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
COMMIT_HASH = REPO.head.object.hexsha

# Docker
CLIENT = docker.from_env()
IMAGE = "seiso/" + NAME


# Tasks
@task
def goat(c):  # pylint: disable=unused-argument
    """Build and run the goat"""
    if not os.environ.get("GITHUB_ACTIONS") == "true":
        environment = {"RUN_LOCAL": "true"}

    buildargs = {"VERSION": VERSION, "COMMIT_HASH": COMMIT_HASH}

    LOG.info("Building %s...", IMAGE)
    CLIENT.images.build(path=str(CWD), rm=True, tag=IMAGE, buildargs=buildargs)
    working_dir = "/tmp/lint/"
    volumes = {CWD: {"bind": working_dir, "mode": "ro"}}
    opinionated_docker_run(
        image=IMAGE, volumes=volumes, working_dir=working_dir, environment=environment,
    )


@task
def publish(c):  # pylint: disable=unused-argument
    """Publish the goat"""
    repository = IMAGE
    LOG.info("Pushing %s to docker hub...", repository)
    CLIENT.images.push(repository=repository)
    LOG.info("Done publishing the %s Docker image", IMAGE)
