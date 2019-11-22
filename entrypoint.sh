#!/bin/bash -l

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
  previous_version_tag=$(git describe --abbrev=0 --match="${version_tag_prefix}*" 2>&1)
  local git_decribe_exit_code=$?
  if [ ${git_decribe_exit_code} -ne 0 ]; then
    if [[ ${previous_version_tag} == *"No names found"* ]]; then
      # Effectively an empty response so return success
      return 0
    else
      return ${git_decribe_exit_code}
    fi
  fi
  echo ${previous_version_tag}
}

get_bump_level_from_git_commit_messages() {
  local bump_level="patch"
  local previous_tag=$1
  if [ -z ${previous_tag} ]; then
    # Return default if no previous tag has been passed
    echo ${bump_level}
  fi
  # Default version bump level is patch
  local commit_messages
  # Get all commit messages since the previous_tag
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

echo "Github Actor: ${GITHUB_ACTOR}"

# Configure git cli tool
git config --global user.email "actions@github.com"
git config --global user.name "${GITHUB_ACTOR}"

# Retrieve current branch name
branch_name=${GITHUB_REF##*/}

# Create tag prefix
version_tag_prefix=${branch_name}/v

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
echo "Previous version: ${previous_version}"

# Get version bump level from previous commit messages
bump_level=$(get_bump_level_from_git_commit_messages ${previous_version_tag}) || die "Failed to retrieve commit messages since previous tag"
echo "Version bump level: ${bump_level}"

# Bump the version number
new_version=$(semver bump ${bump_level} ${previous_version}) || die "Failed to bump the ${bump_level} version of ${previous_version}"

# Add prefix to new version to create the new tag
new_version_tag=${version_tag_prefix}${new_version}

echo "Tagging latest ${branch_name} with ${new_version_tag}"
# Create annotated tag and apply to the current commit
git_tag_result=$(git tag -a ${new_version_tag} -m "Bump ${branch_name} to ${new_version}") || die "Failed to apply tag: ${new_version_tag}"

echo "Pushing tags"
# Output new tag for use in other Github Action jobs
git_push_result=$(git push --tags) || die "Failed to push new tag"

# Output the new tag for future jobs
echo "::set-output name=new_version_tag::${new_version_tag}"

echo "Commit SHA: ${GITHUB_SHA} has been tagged with ${new_version_tag}"
echo "Successfully performed ${GITHUB_ACTION}"
# exit with a non-zero status to flag an error/failure
