#!/bin/bash -l

## Standard ENV variables provided
# ---
echo "GITHUB_ACTION: ${GITHUB_ACTION}: The name of the action"
echo "GITHUB_ACTOR: ${GITHUB_ACTOR}: The name of the person or app that initiated the workflow"
echo "GITHUB_EVENT_PATH: ${GITHUB_EVENT_PATH}: The path of the file with the complete webhook event payload."
echo "GITHUB_EVENT_NAME: ${GITHUB_EVENT_NAME}: The name of the event that triggered the workflow"
echo "GITHUB_REPOSITORY: ${GITHUB_REPOSITORY}: The owner/repository name"
echo "GITHUB_BASE_REF: ${GITHUB_BASE_REF}: The branch of the base repository (eg the destination branch name for a PR)"
echo "GITHUB_HEAD_REF: ${GITHUB_HEAD_REF}: The branch of the head repository (eg the source branch name for a PR)"
echo "GITHUB_REF: ${GITHUB_REF}: The branch or tag ref that triggered the workflow"
echo "GITHUB_SHA: ${GITHUB_SHA}: The commit SHA that triggered the workflow"
echo "GITHUB_WORKFLOW: ${GITHUB_WORKFLOW}: The name of the workflow that triggerdd the action"
echo "GITHUB_WORKSPACE: ${GITHUB_WORKSPACE}: The GitHub workspace directory path. The workspace directory contains a subdirectory with a copy of your repository if your workflow uses the actions/checkout action. If you don't use the actions/checkout action, the directory will be empty

# for logging and returning data back to the workflow,
# see https://help.github.com/en/articles/development-tools-for-github-actions#logging-commands
# echo ::set-output name={name}::{value}
# -- DONT FORGET TO SET OUTPUTS IN action.yml IF RETURNING OUTPUTS

branch_name=${GITHUB_REF##*/}
echo "branch_name: ${branch_name}"
version_tag_prefix=${branch_name}/v
echo "version_tag_prefix: ${version_tag_prefix}"
previous_version_tag=$(git describe --abbrev=0 --match="${version_tag_prefix}*")
echo "previous_version_tag: ${previous_version_tag}"
previous_semantic_version=${previous_version_tag##*/v}
echo "previous_semantic_version: ${previous_semantic_version}"
commit_messages_since_last_version=$(git log --pretty=oneline HEAD...${previous_version_tag})
echo "commit_messages_since_last_version: ${commit_messages_since_last_version}"

version_bump_level=patch

if [[ $commit_messages_since_last_version == *"#major"* ]]; then
  version_bump_level=major
elif [[ $commit_messages_since_last_version == *"#minor"* ]]; then
  version_bump_level=minor
fi
echo "version_bump_level: ${version_bump_level}"

new_version=$(semver -i ${version_bump_level} ${previous_semantic_version})
echo "new_version: ${new_version}"
new_version_tag=${version_tag_prefix}${new_version}
echo "new_version_tag: ${new_version_tag}"

git_tag_result=$(git tag -a ${new_version_tag} -m "Bumping ${branch_name} version to ${new_version}")
echo "git_tag_result: ${git_tag_result}"
git_tag_status=$?
echo "git_tag_status: ${git_tag_status}"

git_push_result=$(git push --tags)
echo "git_push_result: ${git_push_result}"
git_push_status=$?
echo "git_push_status: ${git_push_status}"
echo "FINISHED"
# exit with a non-zero status to flag an error/failure
