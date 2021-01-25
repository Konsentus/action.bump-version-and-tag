#!/bin/bash -l

# Convenience function to output an error message and exit with non-zero error code
die() {
	local _ret=$2
	test -n "$_ret" || _ret=1
	printf "$1\n" >&2
	exit ${_ret}
}

get_previous_version_tag() {
  local tag_prefix=$1
  local previous_version_tag

  # Get last annoted tag that has the version tag prefix
  # stderr redirected to stdout to collect any error messages
  previous_version_tag=$(git describe --abbrev=0 --tags --match="${version_tag_prefix}?*.?*.?*" 2>&1)
  local git_decribe_exit_code=$?

  if [ ${git_decribe_exit_code} -ne 0 ]; then
    if [[ ${previous_version_tag} == *"No names found"* ]]; then
      # Effectively an empty response so return success
      return 0
    else
      # Something else went wrong, print error to stderr and exit with non zero
      echo ${previous_version_tag} >&2
      return ${git_decribe_exit_code}
    fi
  fi

  # everything went fine and the previous version_tag was found
  echo ${previous_version_tag}
}

get_bump_level_from_git_commit_messages() {
  local previous_tag=$1
  local bump_level="patch"
  local commit_messages

  if [ -z ${previous_tag} ]; then
    # Return default if no previous tag has been passed
    echo ${bump_level}
    return 0
  fi

  # Default version bump level is patch
  # Get all commit titles since the previous_tag
  commit_messages=$(git log --pretty=oneline HEAD...${previous_tag})
  local git_log_exit_code=$?

  if [ ${git_log_exit_code} -ne 0 ]; then
    return ${git_log_exit_code}
  fi

  # Search commit messages for presence of #major or #minor to determine verison bump level
  # #major takes precedence
  if [[ $commit_messages == *"#major"* ]]; then
    bump_level="major"
  elif [[ $commit_messages == *"#minor"* ]]; then
    bump_level="minor"
  fi

  echo ${bump_level}
}

is_hotfix() {
  source_branch=$(hub api /repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls -H "accept: application/vnd.github.groot-preview+json" | jq .[0].head.label)
  if [[ ${source_branch} == *"hotfix/"* ]]; then
    return 0
  fi
  return 1
}

move_previous_tag() {
  local previous_version_tag=$1
  local current_commit_sha=$2

  # force reuse of previous tag, will remove it from its original commit
  git tag -a -m "Hotfix applied" "${previous_version_tag}" "${current_commit_sha}" -f
  if [ $? -ne 0 ]; then
    echo "Failed to move tag for hotfix" >&2
    return 1
  fi
  # force push of moved tag
  git push origin --tags -f
  if [ $? -ne 0 ]; then
    echo "Failed to push hotfix tag" >&2
    return 1
  fi
}

# Configure git cli tool
git config --global user.email "actions@github.com"
git config --global user.name "${GITHUB_ACTOR}"
remote_repo="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# Retrieve current branch name
branch_name=${GITHUB_REF##*/}

# Create tag prefix
if [ "${INPUT_PREFIX}" == "{default}" ]; then
  version_tag_prefix=${branch_name}/v
else
  version_tag_prefix=${INPUT_PREFIX}
fi

# Retrieve previous tag that matches the version tag prefix
previous_version_tag=$(get_previous_version_tag ${version_tag_prefix}) || die "Failed to retrieve previous tags"

if [ -z ${previous_version_tag} ]; then
  # No previous version tag found. Setting previous version to be 0.0.0
  previous_version="0.0.0"
else
  # A previous tag matching the tag prefix was found, output it for future steps
  echo "::set-output name=previous_version_tag::${previous_version_tag}"
  previous_version=${previous_version_tag#${version_tag_prefix}}
fi
echo "Previous version tag: ${previous_version_tag:-"Not found"}"

# Perform check do determine if this was triggered by a hotfix
if is_hotfix; then
  echo "Hotfix detected. Moving previous version tag to current latest on ${branch_name}"
  # move_previous_tag "${previous_version_tag}" "${GITHUB_SHA}" || die "Failed to move tag for hotfix"
  new_version_tag=${previous_version_tag}
  tag_message="Apply hotfix, moving ${previous_version_tag} to latest ${branch_name}"
else
  # Get version bump level from previous commit messages
  bump_level=$(get_bump_level_from_git_commit_messages ${previous_version_tag}) || die "Failed to retrieve commit messages since previous tag"
  echo "Version bump level: ${bump_level}"

  # Bump the version number
  new_version=$(semver bump ${bump_level} ${previous_version}) || die "Failed to bump the ${bump_level} version of ${previous_version}"
  new_version_tag=${version_tag_prefix}${new_version}
  tag_message="Bump ${branch_name} tag from ${previous_version_tag} to ${new_version_tag}"
fi
# Add prefix to new version to create the new tag

echo "Tagging latest ${branch_name} with ${new_version_tag}"
# Create annotated tag and apply to the current commit
git tag -a -m "${tag_message}" "${new_version_tag}" "${GITHUB_SHA}" -f || die "Failed to ${tag_message}"

echo "Pushing tags"
git push "${remote_repo}" --tags -f || die "Failed to push ${tag_message}"

# Output new tag for use in other Github Action jobs
echo "::set-output name=new_version_tag::${new_version_tag}"
echo "Commit SHA: ${GITHUB_SHA} has been tagged with ${new_version_tag}"
echo "Successfully performed ${GITHUB_ACTION}"
# exit with a non-zero status to flag an error/failure
