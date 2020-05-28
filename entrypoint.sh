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
  previous_version_tag=$(git describe --abbrev=0 --match="${version_tag_prefix}*" 2>&1)
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

check_is_hotfix() {
  local previous_commit
  local branch_list
  local number_of_branches

  # get ancestor commit.
  previous_commit=$(git rev-parse "${GITHUB_SHA}"^1) || return 1
  # get list of branches (from remote) that contain the ancestor commit
  branch_list=$(git branch --contains="${previous_commit}" -r) || return 1
  # count new lines to get number of branches
  number_of_branches=$(wc -l <<<"${branch_list}") || return 1
  # trim whitespace returned from wc command
  number_of_branches=$(echo -n "${number_of_branches//[[:space:]]/}")

  # if there are exactly two branches, one of which is a "hotfix" branch and the other is the current branch
  # then this is considered a hotfix
  if [[ number_of_branches -eq "2" ]] && [[ ${branch_list}==*"hotfix/"* ]] && [[ ${branch_list}==*"${branch_name}"* ]]; then
    echo true
    return 0
  fi

  echo false
  return 0
}

bump_package_dot_json() {
  local version=$1
  npm version ${version} || die "Failed to bump package.json version to ${version}"
}

# Configure git cli tool
git config --global user.email "actions@github.com"
git config --global user.name "${GITHUB_ACTOR}"
remote_repo="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# Retrieve current branch name
branch_name=${GITHUB_REF##*/}

main_release_branch=${INPUT_MAIN_RELEASE_BRANCH}

# Create tag prefix
version_tag_prefix="${branch_name}/v"

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
is_hotfix=$(check_is_hotfix) || die "failed to check if hotfix"

if [ "${is_hotfix}" == false ]; then
  # Get version bump level from previous commit messages
  bump_level=$(get_bump_level_from_git_commit_messages ${previous_version_tag}) || die "Failed to retrieve commit messages since previous tag"
  echo "Version bump level: ${bump_level}"

  # Bump the version number
  new_version=$(semver bump ${bump_level} ${previous_version}) || die "Failed to bump the ${bump_level} version of ${previous_version}"
  new_version_tag=${version_tag_prefix}${new_version}
  tag_message="Bump ${branch_name} tag from ${previous_version_tag} to ${new_version_tag}"
else
  echo "Hotfix detected. Moving previous version tag to current latest on ${branch_name}"
  new_version=${previous_version}
  new_version_tag=${previous_version_tag}
  tag_message="Apply hotfix, moving ${previous_version_tag} to latest ${branch_name}"
fi

echo "::set-output name=new_version_tag::${new_version_tag}"
echo "::set-output name=tag_message::${tag_message}"

if [[ -f "./package.json" ]] && [[ ${main_release_branch}==${branch_name} ]]; then
  npm version "${new_version}" --no-git-tag-version
  git commit -am "Bump package.json version to ${new_version}"
  npm run publish --if-present
fi

echo "Tagging latest ${branch_name} with ${new_version_tag}"
# Create annotated tag and apply to the current commit
git tag -a -m "${tag_message}" "${new_version_tag}" "${GITHUB_SHA}" -f || die "Failed to ${tag_message}"

echo "Pushing tags"
git push "${remote_repo}" --follow-tags -f || die "Failed to push ${tag_message}"

# Output new tag for use in other Github Action jobs
echo "Commit SHA: ${GITHUB_SHA} has been tagged with ${new_version_tag}"
echo "Successfully performed ${GITHUB_ACTION}"
