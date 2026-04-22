# Contributing Guidelines

## Branch Policy
- **Base Branch:** `dev`. All development must be based on the `dev` branch.
- Please create a separate feature-branch from `dev`, commit your changes to it, and then open a Pull Request into `dev`.
  
  *Example:*
  ```bash
  git checkout dev
  git checkout -b feature/your-change
  # ... make your changes and commit them
  git push origin feature/your-change
  ```

## Pull Request Rules
- **Required Reviewers:** PRs require review from at least one Core Reviewer before merging.
- **Merge Cadence:** Changes from `dev` are merged to `main` weekly by the mentor.
- **Commit Messages:** Follow standard semantic commit messages (e.g. `feat:`, `chore:`, `fix:`, `docs:`, `refactor:`).
- **Merge Rules:** Use **Squash and Merge** when merging feature branches to keep the history clean.
