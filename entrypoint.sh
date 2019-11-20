#!/bin/bash -l

git config --global user.email "actions@github.com"
git config --global user.name "${GITHUB_ACTOR}"

branch_name=${GITHUB_REF##*/}

version_tag_prefix=${branch_name}/v
echo "version_tag_prefix:${version_tag_prefix}"

# previous_version_tag=$(git describe --abbrev=0 --match="${version_tag_prefix}*")

previous_version_tag=$(git describe --abbrev=0 --match="${version_tag_prefix}*")

if [ -z "${previous_version_tag}" ]; then
  echo "Failed to find any previous version tags with the prefix ${version_tag_prefix}. Initial version will be 0.0.0"
  new_version=0.0.0
else
  echo "previous_version_tag:${previous_version_tag}"

  previous_semantic_version=${previous_version_tag##*/v}
  echo "previous_semantic_version:${previous_semantic_version}"

  commit_messages_since_last_version=$(git log --pretty=oneline HEAD...${previous_version_tag})
  echo "commit_messages_since_last_version:${commit_messages_since_last_version}"

  version_bump_level=patch

  if [[ $commit_messages_since_last_version == *"#major"* ]]; then
    version_bump_level=major
  elif [[ $commit_messages_since_last_version == *"#minor"* ]]; then
    version_bump_level=minor
  fi

  echo "version_bump_level:${version_bump_level}"

  new_version=$(semver bump "${version_bump_level}" "${previous_semantic_version}")
  echo "new_version:${new_version}"
fi

new_version_tag=${version_tag_prefix}${new_version}
echo "new_version_tag:${new_version_tag}"

git_tag_result=$(git tag -a ${new_version_tag} -m "Bump ${branch_name} to ${new_version}")
echo "git_tag_result: ${git_tag_result}"
git_tag_status=$?
echo "git_tag_status: ${git_tag_status}"

git_push_result=$(git push --tags)
echo "git_push_result: ${git_push_result}"
git_push_status=$?
echo "git_push_status: ${git_push_status}"
echo "FINISHED"
# exit with a non-zero status to flag an error/failure
