# Release Automation

Coin-Ops uses `release-please` to automate semantic version releases from Conventional Commit style PR titles and squash merge commit titles.

## Branch Model

- `dev` is the integration branch for normal team work.
- `main` is the stable release branch.
- `Shabat` continues to publish `shabat-latest`.
- `dev` continues to publish `dev-latest`.
- Git tags named `vX.Y.Z` continue to publish immutable versioned images.

Release automation runs only on pushes to `main`. It does not run on `dev` or `Shabat`.

## Tooling Choice

This repo uses `release-please` because it is designed for GitHub Actions, Conventional Commits, changelog generation, SemVer calculation, GitHub Releases, and `vX.Y.Z` tag creation.

The source of truth for version bumps is the squash merge commit title on `main`. In practice, that means the PR title should already follow the release rule before it is squash-merged.

## Version Bump Rules

Use these PR titles or squash merge commit titles:

| Change type | Example title | Version bump |
| --- | --- | --- |
| Bug fix | `fix: correct history API status code` | patch, for example `v1.2.3` -> `v1.2.4` |
| Compatible feature | `feat: add price history endpoint` | minor, for example `v1.2.3` -> `v1.3.0` |
| Breaking change | `feat!: change public API response shape` | major, for example `v1.2.3` -> `v2.0.0` |
| Breaking change footer | `BREAKING CHANGE: response format changed` | major |

Non-release changes such as `docs:`, `chore:`, `ci:`, and `test:` can appear in the changelog configuration, but they do not trigger a release by themselves.

## Maintainer Workflow

1. Merge feature work into `dev` through normal pull requests.
2. Promote approved, stable work from `dev` to `main`.
3. When `main` receives release-worthy commits, `release-please` opens or updates a release PR.
4. Review the release PR changelog and version bump.
5. Merge the release PR into `main`.
6. `release-please` creates the GitHub Release and pushes the `vX.Y.Z` tag.
7. The existing Docker image workflow runs from that tag and publishes versioned GHCR images.

## GitHub Token Behavior

The release workflow uses the default GitHub Actions token provided by the repository. No extra repository secret is required for the initial setup.

Tags created by the default `GITHUB_TOKEN` do not trigger new workflow runs from `push` events. This is expected GitHub behavior that prevents recursive workflow loops.

To keep release automation secret-free, the release workflow explicitly dispatches the existing Docker image workflow with `workflow_dispatch` after release-please creates a `vX.Y.Z` tag. The Docker workflow already supports `workflow_dispatch` and tag refs, so it can publish the versioned images for that release tag.

If maintainers later prefer natural tag-triggered Docker publishing instead of explicit dispatch, release-please can be switched to a GitHub App token or Personal Access Token.

## Existing Docker Compatibility

The Docker workflow already listens for tags matching `v*.*.*`. This release workflow only creates those tags; it does not change the Docker image build matrix and does not change `dev-latest` or `shabat-latest` behavior.
