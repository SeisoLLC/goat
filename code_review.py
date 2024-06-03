#!/usr/bin/env python3
"""
salacious-code-reviews script entrypoint
"""

import ast
import json
import os
import re

import openai
from github import Github, GithubException, PullRequest
from openai import OpenAI

from code_reviews import config, constants


def get_github_session() -> Github:
    log.info("Creating GitHub Session...")

    if not os.getenv("GITHUB_TOKEN"):
        log.error("No GITHUB_TOKEN environment variable was detected")
        raise SystemExit(0)

    return Github(os.getenv("GITHUB_TOKEN"))


def get_openai_session() -> OpenAI:
    log.info("Setting up OpenAI Session...")

    if not os.getenv("OPENAI_API_KEY"):
        log.error("No OPENAI_API_KEY environment variable was detected")
        raise SystemExit(0)

    return OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


def get_repo_and_pr() -> dict:
    repo_and_pr: dict[str, list[object]] = {}
    repo_and_pr = {"repo": [], "pr": []}
    github_ref = os.getenv("GITHUB_REF")
    github_repo = os.getenv("GITHUB_REPOSITORY")

    log.info("Getting repo and pull request from runner environment...")

    if not github_ref:
        log.error("Failed to find the GITHUB_REF environment variable")
        raise SystemExit(1)

    # If the split from GITHUB_REF is not an int, exit
    parts = github_ref.split("/")
    if "pull" in parts:
        try:
            pr_index = parts.index("pull") + 1
            pr_number = int(parts[pr_index])
            repo_and_pr["pr"].append(pr_number)
        except (ValueError, IndexError):
            log.error(f"GITHUB_REF does not contain a valid PR number: {github_ref}")
            raise SystemExit(1)
    else:
        log.warn("Not running on a pull request; skipping the Salacious code review...")
        raise SystemExit(0)

    if not github_repo:
        log.error("Cannot get repository name, exiting!")
        raise SystemExit(1)

    repo_and_pr["repo"].append(github_repo)

    return repo_and_pr


def do_code_review(gh_session: Github, repo_and_pr: dict, ai_client: OpenAI):
    comments = []
    skipped_files = []
    repo = gh_session.get_repo(repo_and_pr["repo"][0])
    pr = repo.get_pull(repo_and_pr["pr"][0])

    log.info(f"Performing analysis on pull request {pr.number} for {repo.name}...")

    changed_files = pr.get_files()

    for item in changed_files:
        log.info(f"Having Salacious review diff for {item.filename}...")
        if not type(item) == "str":
            if item.patch is None:
                log.warning(f"Skipping empty source file {item.filename}...")
            elif len(item.patch) > constants.MAX_TOKENS:
                log.warning(
                    f"Skipping {item.filename} as size {len(item.patch)} exceeds the "
                    f"limit of {constants.MAX_TOKENS} consider smaller commits..."
                )
                skipped_files.append(item.filename)
            else:
                diff_comment = submit_to_gpt(
                    f"filename: {item.filename} ** {item.patch}",
                    ai_client=ai_client,
                )
                if "comments" in diff_comment:
                    comments.append(json.dumps(diff_comment["comments"]))
                    log.info(f"Salacious has completed review of {item.filename}...")
                else:
                    log.error(
                        f"Salacious has failed review of {item.filename} trying again..."
                    )
                    diff_comment = submit_to_gpt(
                        f"filename: {item.filename} ** {item.patch}",
                        ai_client=ai_client,
                    )
                    if "comments" in diff_comment:
                        comments.append(json.dumps(diff_comment["comments"]))
                        log.info(
                            f"Salacious has completed review of {item.filename}..."
                        )
                    else:
                        log.error(
                            f"Salacious has failed review of {item.filename} again giving up..."
                        )
                        skipped_files.append(item.filename)

    log.info("Analysis complete, submitting review...")

    if len(skipped_files) > 0:
        log.error(f"The following files were skipped {skipped_files}...")

    submit_review(comments=comments, pr=pr, skipped_files=skipped_files)


def submit_review(
    comments: list, pr: PullRequest.PullRequest, skipped_files: list
) -> None:
    review_body = "Salacious has reviewed your code, please see inline comments."

    if skipped_files:
        review_body += f"\n\n List of skipped files:\n{skipped_files}"

    if not os.getenv("GITHUB_TOKEN"):
        log.error("Please provide a valid GITHUB_TOKEN environment variable!")
        raise SystemExit(1)

    os.getenv("GITHUB_TOKEN")

    log.debug(f"{comments=}")

    try:
        if not comments:
            raise ValueError("The comments list is empty.")

        comments_object = [comment for comment in ast.literal_eval(comments[0])]
        pr.create_review(body=review_body, event="COMMENT", comments=comments_object)

    except ValueError as err:
        log.error(f"Failed to submit review due to the following error: {err}!")

    except GithubException as err:
        log.error(f"Failed to submit review due the following error: {err}!")

    log.info("Submitted pull request review, Salacious B. Crumb signing off!")


def submit_to_gpt(code: str, ai_client: OpenAI) -> dict:
    review = {}

    def sanitize_json_string(json_string):
        """Sanitize the JSON string to ensure it can be parsed."""
        # Strip surrounding backticks and 'json' identifier
        if json_string.startswith("```") and json_string.endswith("```"):
            json_string = json_string.strip("```").strip()
        if json_string.startswith("json"):
            json_string = json_string[4:].strip()

        # Remove any trailing commas
        json_string = re.sub(r",\s*([\]}])", r"\1", json_string)

        return json_string

    try:
        completion = ai_client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "".join(constants.PROMPT)},
                {"role": "user", "content": code},
            ],
        )

        # Log the entire completion object for debugging
        log.debug(f"Completion object: {completion}")

        # Ensure the structure of the response
        if (
            completion
            and hasattr(completion, "choices")
            and len(completion.choices) > 0
        ):
            content = completion.choices[0].message.content
            log.debug(f"Completion message content: {content}")

            # Sanitize the content to ensure it's valid JSON
            sanitized_content = sanitize_json_string(content)
            log.debug(f"Sanitized content: {sanitized_content}")

            try:
                review = json.loads(sanitized_content)
            except json.JSONDecodeError as e:
                log.error(f"Received malformed JSON response: {sanitized_content}")
                log.error(f"JSONDecodeError: {str(e)}")
            except Exception as e:
                log.error(f"Unexpected error when parsing JSON: {str(e)}")
        else:
            log.error(
                "ChatCompletion object does not contain expected 'choices' or 'message' structure"
            )

    except openai.RateLimitError as err:
        log.error(f"Salacious failed due to an exceeded rate limit: {err}")
    except openai.APIError as err:
        log.error(f"Salacious failed due to API error: {err}")
    except Exception as e:
        log.error(f"Salacious failed due to unexpected error during API call: {str(e)}")

    return review


def main():
    ai_client = get_openai_session()
    gh_session = get_github_session()
    repo_and_pr = get_repo_and_pr()
    do_code_review(gh_session=gh_session, repo_and_pr=repo_and_pr, ai_client=ai_client)


if __name__ == "__main__":
    log = config.setup_logging()
    log.info(f"Starting {config.__project_name__} v{config.__version__}...")
    main()
