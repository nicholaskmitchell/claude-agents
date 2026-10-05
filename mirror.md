<!-- Canonical copy: the claude-agents repository. Edit it there; do not edit a copy. -->
## Repositories mirrored from GitLab

Before you push, or open or merge a pull request or a merge request, find out whether the repository you are about to push to (each one, if several are attached) is mirrored: it belongs to `nicholaskmitchell`, and `main` on its remote contains the file `.github/workflows/sync-to-gitlab.yml`. Look on the remote, not in the working tree, because a clone or a branch that is behind may not have the file yet: after `git fetch`, `git cat-file -e origin/main:.github/workflows/sync-to-gitlab.yml` succeeds when it is there. A mirrored repository lives on GitLab, at `gitlab.com/nicholaskmitchell/<name>`, and `github.com/nicholaskmitchell/<name>` is a mirror: GitLab overwrites GitHub's `main` whenever its own `main` changes. The rest of this section applies to mirrored repositories only.

If your `origin` is not on gitlab.com (a cloud session, or a contributor's clone from GitHub):

- Work on a branch and open a pull request. Never push to `main` on GitHub: the next mirror update overwrites it, so that work would be lost.
- Open the pull request as soon as the branch has work worth keeping. A branch that is pushed without a pull request never reaches GitLab, because only pull requests are copied across.
- A pull request is copied to a GitLab merge request automatically, and the maintainer merges it on GitLab. Never merge a pull request on GitHub: that changes only GitHub's `main`, which the mirror then overwrites.
- Merges are fast-forward only, so that commit IDs match and GitHub can mark the pull request merged. Before asking for a merge, make sure the branch contains the latest `main`: merge `main` into it and push. Do not rebase a branch that already has a pull request, because pushing it again would need a forced push.
- Issues and their comments sync both ways. Branches on GitLab other than `main`, and merge requests opened on GitLab, exist only there, so they cannot be seen from GitHub.

If your `origin` is on gitlab.com (the maintainer's machine):

- Push branches and `main` to `origin` as usual. Only `main` and tags are mirrored, and GitHub's `main` follows within about a minute. Never push to or merge into `main` on GitHub.
- A pull request from GitHub arrives as a merge request from a branch named `gh-pr-<number>`. Merge it on GitLab, fast-forward. If it is behind `main`, bring the pull request's branch up to date on GitHub with `gh pr update-branch <number> -R nicholaskmitchell/<name>`, or ask the session that owns the branch to merge `main` in; the merge request then updates by itself. (The pull request page has an "Update branch" button that does the same, but only when the repository setting "Always suggest updating pull request branches" is on.) Do not use GitLab's Rebase: it changes the commit IDs, and the pull request then stays open on GitHub and has to be closed by hand.
