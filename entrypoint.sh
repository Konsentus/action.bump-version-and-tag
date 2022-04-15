#!/bin/bash -l

# Since Git v2.35.2 current working directory should be set as safe explicitly (fix for CVE-2022-24765)
git config --global --add safe.directory ${PWD}

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
    if [[ ${previous_version_tag} == *"No names found"* ]] || [[ ${previous_version_tag} == *"No tags can describe"* ]]; then
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

generate_required_status_checks() {
  local original=$1
  local result=
  if [ "$(echo -E $original | jq '.required_status_checks == null')" == "true" ]; then
    result='null'
  else
    result=$(jq -n \
      --argjson required_status_checks_strict "$(echo -E $original | jq '.required_status_checks.strict // false')" \
      --argjson required_status_checks_contexts "[$(echo -E $original | jq '.required_status_checks.contexts[]?' -c | tr '\n' ',' | sed 's/,$//')]" \
      '{
            "strict": $required_status_checks_strict,
            "contexts": $required_status_checks_contexts
        }')
  fi

  echo $result
}

generate_required_pull_request_reviews() {
  local original=$1
  local result=
  if [ "$(echo -E $original | jq '.required_pull_request_reviews == null')" == "true" ]; then
    result='null'
  else
    result=$(jq -n \
      --argjson required_pull_request_reviews_dismissal_restrictions_users "[$(echo -E $original | jq '.required_pull_request_reviews.dismissal_restrictions.users[]?.login' -c | tr '\n' ',' | sed 's/,$//')]" \
      --argjson required_pull_request_reviews_dismissal_restrictions_teams "[$(echo -E $original | jq '.required_pull_request_reviews.dismissal_restrictions.teams[]?.login' -c | tr '\n' ',' | sed 's/,$//')]" \
      --argjson required_pull_request_reviews_dismiss_stale_reviews "$(echo -E $original | jq '.required_pull_request_reviews.dismiss_stale_reviews // false')" \
      --argjson required_pull_request_reviews_require_code_owner_reviews "$(echo -E $original | jq '.required_pull_request_reviews.require_code_owner_reviews // false')" \
      --argjson required_pull_request_reviews_required_approving_review_count "$(echo -E $original | jq '.required_pull_request_reviews.required_approving_review_count // 1')" \
      '{
            "dismissal_restrictions": {
                "users": $required_pull_request_reviews_dismissal_restrictions_users,
                "teams": $required_pull_request_reviews_dismissal_restrictions_teams
            },
            "dismiss_stale_reviews": $required_pull_request_reviews_dismiss_stale_reviews,
            "require_code_owner_reviews": $required_pull_request_reviews_require_code_owner_reviews,
            "required_approving_review_count": $required_pull_request_reviews_required_approving_review_count
        }')
  fi

  echo $result
}

generate_restrictions() {
  local original=$1
  local result=
  if [ "$(echo -E $original | jq '.restrictions == null')" == "true" ]; then
    result='null'
  else
    result=$(jq -n \
      --argjson restrictions_users "[$(echo -E $original | jq '.restrictions.users[]?.login' -c | tr '\n' ',' | sed 's/,$//')]" \
      --argjson restrictions_teams "[$(echo -E $original | jq '.restrictions.teams[]?.slug' -c | tr '\n' ',' | sed 's/,$//')]" \
      --argjson restrictions_apps "[$(echo -E $original | jq '.restrictions.apps[]?.slug' -c | tr '\n' ',' | sed 's/,$//')]" \
      '{
            "users": $restrictions_users,
            "teams": $restrictions_teams,
            "apps": $restrictions_apps
        }')
  fi

  echo $result
}

generate_branch_protection() {
  local original=$1

  local result=$(jq -n \
    --argjson required_status_checks "$(generate_required_status_checks $original)" \
    --argjson enforce_admins_enabled "$(echo -E $original | jq '.enforce_admins.enabled // false')" \
    --argjson required_pull_request_reviews "$(generate_required_pull_request_reviews $original)" \
    --argjson restrictions "$(generate_restrictions $original)" \
    '{
        "required_status_checks": $required_status_checks,
        "enforce_admins": $enforce_admins_enabled,
        "required_pull_request_reviews": $required_pull_request_reviews,
        "restrictions": $restrictions
    }')

  if [ "$?" -ne 0 ]; then
    echo "Error when attempting to generate branch protection"
    exit 2
  fi

  echo $result
}

# Configure git cli tool
git config --global user.email "actions@github.com"
git config --global user.name "${GITHUB_ACTOR}"
remote_repo="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# Retrieve current branch name
branch_name=${GITHUB_REF##*/}

main_release_branch=${INPUT_RELEASE_BRANCH}

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
# is_hotfix=$(check_is_hotfix) || die "failed to check if hotfix"

if is_hotfix; then
  echo "Hotfix detected. Moving previous version tag to current latest on ${branch_name}"
  new_version=${previous_version}
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

echo "::set-output name=new_version_tag::${new_version_tag}"
echo "::set-output name=tag_message::${tag_message}"

if [[ -f "./package.json" ]] && [[ ${release_branch}==${branch_name} ]]; then
  echo "Bumping package.json to ${new_version}"
  npm version "${new_version}" --no-git-tag-version
  echo "Commiting updated package.json"
  git commit -am "Bump package.json version to ${new_version}"
fi

echo "Tagging latest ${branch_name} with ${new_version_tag}"
# Create annotated tag and apply to the current commit
git tag -a -m "${tag_message}" "${new_version_tag}" -f || die "Failed to ${tag_message}"

echo "Checking branch protection"
echo "hub api repos/${GITHUB_REPOSITORY}/branches/${branch_name}/protection"
current_protection=$(hub api repos/${GITHUB_REPOSITORY}/branches/${branch_name}/protection 2>&1)
current_protection_status=$?

if [ "$current_protection_status" -eq "0" ]; then
  echo "${branch_name} : Remove branch protection"
  hub api -X DELETE repos/${GITHUB_REPOSITORY}/branches/${branch_name}/protection
else
  die "Failed to retrieve branch protection: ${current_protection}"
fi

echo "Pushing tags"
git push "${remote_repo}" --follow-tags --force || die "Failed to push ${tag_message}"

if [ "$current_protection_status" -eq "0" ]; then
  echo "${branch_name} : Re-enable branch protection"
  # Custom header is required for setting number of required pull request reviews
  # see https://developer.github.com/v3/repos/branches/#get-branch-protection
  echo $(generate_branch_protection ${current_protection}) |
    hub api -X PUT repos/${GITHUB_REPOSITORY}/branches/${branch_name}/protection -H "accept: application/vnd.github.luke-cage-preview+json" --input -
fi

# Output new tag for use in other Github Action jobs
echo "Commit SHA: ${GITHUB_SHA} has been tagged with ${new_version_tag}"
echo "Successfully performed ${GITHUB_ACTION}"
