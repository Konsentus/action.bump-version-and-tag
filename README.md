# Bump Version and Tags

[secrets.GITHUB_TOKEN](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/authenticating-with-the-github_token)

## Versioning

Versioning is performed with the SemVer format (_major_._minor_._patch_). By default the _patch_ number will be incremented on merge. _Major_ and _minor_ bumps are be controlled by the keywords `#major` and `#minor` found in the commit messages. In the case of multiple keywords, `#major` takes priority.

As tags will be specific to the branch they are on, tags will be in the form of `[BRANCH_NAME]/1.0.0`.

## Hotfixes

In the case of merging a _hotfix_ branch, the previous tag on that particular branch will be moved to the current commit.
