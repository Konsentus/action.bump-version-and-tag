#!/bin/bash -l

# Configure git cli tool
git config --global user.email "actions@github.com"
git config --global user.name "${GITHUB_ACTOR}"

# Retrieve current branch name
branch_name=${GITHUB_REF##*/}

# Create tag prefix
version_tag_prefix=${branch_name}/v

# Get last annotated tag from previous commits, matching the tag prefix pattern
previous_version_tag=$(git describe --abbrev=0 --match="${version_tag_prefix}*")

if [ $? -ne 0 ] || [ -z "${previous_version_tag}" ]; then
  # No previous tag found, so start version at 0.0.0
  echo "Failed to find any previous version tags with the prefix ${version_tag_prefix}. Initial version will be 0.0.0"
  new_version=0.0.0
else
  echo "::set-output name=previous_version_tag::${previous_version_tag}"

  # Strip prefix from the previous version tag
  previous_semantic_version=${previous_version_tag#${version_tag_prefix}}

  # Gather commit message from all commits since the last version tag to now
  commit_messages_since_last_version=$(git log --pretty=oneline HEAD...${previous_version_tag})

  # Default version bump level is patch
  version_bump_level=patch

  # Search commit messages for presence of #major or #minor to determine verison bump level
  # #major takes precedence
  if [[ $commit_messages_since_last_version == *"#major"* ]]; then
    version_bump_level=major
  elif [[ $commit_messages_since_last_version == *"#minor"* ]]; then
    version_bump_level=minor
  fi

  echo "Performing a ${version_bump_level} bump on the previouss version: ${previous_semantic_version}"

  # Bump previous version with bump level
  new_version=$(semver bump "${version_bump_level}" "${previous_semantic_version}")
fi

# Add prefix to new version
new_version_tag=${version_tag_prefix}${new_version}

# Create annotated tag and apply to the current commit
git_tag_result=$(git tag -a ${new_version_tag} -m "Bump ${branch_name} to ${new_version}")
echo "git_tag_result: ${git_tag_result}"
git_tag_status=$?
echo "git_tag_status: ${git_tag_status}"

# Output new tag for use in other Github Action jobs
echo "::set-output name=new_version_tag::${new_version_tag}"
git_push_result=$(git push --tags)
echo "git_push_result: ${git_push_result}"
git_push_status=$?
echo "git_push_status: ${git_push_status}"
echo "FINISHED"
# exit with a non-zero status to flag an error/failure
