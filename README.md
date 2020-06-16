# Bump Version and Tags

This action will find the last version tag made on the current branch, bump it and tag the current commit with the new version. If a package.json file is present, the version contained will also be bumped to the same version as the tag. As tags are commit specific and not branch specific, these version tags are prefixed with the current branch name, e.g. master/v1.0.0.

## Usage

### Example Pipeline

```yaml

name: Bump Version and Tag
on:
  push:
    branches:
      - 'master'
      - 'sit'
      - 'alpha'
      - 'sandbox'
jobs:
  bump-and-tag:
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    name: Bump and Tag
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v2
        with:
          fetch-depth: 0

      - name: Get Tags
        run: git fetch origin +refs/tags/*:refs/tags/*

      - name: Bump Version
        id: bump_and_tag
        uses: konsentus/action.bump-version-and-tag@v2

```

## Environment Variable

- `GITHUB_TOKEN`: GitHub provides a token that you can use to authenticate on behalf of GitHub Actions as described in [Authenticating with the GITHUB_TOKEN](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets).

## Optional Inputs

- `release_branch`: The branch name that contains the final release. If the target branch is the release_branch then this action will attempt to bump the package.json version, if the file exists.
  - Default value: `"production"`

## Outputs

- `old_image_digest`: In the case that a Docker image tagged with the branch name already exists in the AWS ECR repository, this output variable will hold the value of the Docker image digest. If there are no Docker images tagged with the branch name, then this will be empty.
- `new_image_digest`: This output variable will hold the Docker image digest of the newly built image.

## Versioning

Versioning is performed with the SemVer format (_major_._minor_._patch_). By default the _patch_ number will be incremented on merge. _Major_ and _minor_ bumps are be controlled by the keywords `#major` and `#minor` found in the commit messages created since the lat version. In the case of multiple keywords, `#major` takes priority.

As tags will be specific to the branch they are on, tags will be in the form of `[BRANCH_NAME]/1.0.0`.

## Hotfixes

In the case of merging a _hotfix_ branch, the previous tag on that particular branch will be moved to the current commit.

## Action flow

The diagram below illustrates the operational flow of this action.

![Action Flow](./docs/action-flow.drawio.png)
