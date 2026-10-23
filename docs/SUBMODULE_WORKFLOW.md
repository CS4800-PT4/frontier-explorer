# Submodule workflow

The repositories under `external/` are independent Git repositories managed as
submodules of `frontier-explorer`.

There are two separate Git operations when a dependency changes:

1. Commit and push the change inside the submodule repository.
2. Commit and push the updated submodule commit reference from `frontier-explorer`.

Pushing a change inside a submodule does not update the parent repository by
itself.

## Initial setup

Clone the parent repository:

```bash
git clone https://github.com/CS4800-PT4/frontier-explorer.git
cd frontier-explorer
```

Initialize and download all submodules, including nested submodules:

```bash
git submodule update --init --recursive
```

This checks out each submodule at the exact commit recorded by
`frontier-explorer`.

## Remotes

Each submodule should normally use these remote names:

- `origin`: the CS4800-PT4 organization fork, where project changes are pushed.
- `upstream`: the original public repository, used to fetch upstream changes.

Check the remotes from the root of the submodule:

```bash
git remote -v
```

Do not run these commands from a nested package directory such as
`mavros_msgs`; run them from the repository root, such as
`external/mavros_ws/src/mavros`.

If a submodule does not yet have the organization fork as `origin`, configure
it once:

```bash
git remote rename origin upstream
git remote add origin https://github.com/CS4800-PT4/REPOSITORY.git
```

Replace `REPOSITORY` with the fork name. Verify the result before pushing:

```bash
git remote -v
```

## Update a submodule

The following example updates PX4. The same process applies to the other
submodules.

Enter the submodule and inspect its state:

```bash
cd /home/general_use_account/frontier-explorer/external/PX4-Autopilot
git status
git branch --show-current
```

If Git reports a detached `HEAD` and you are going to make changes, create a
branch before editing:

```bash
git switch -c branch-name
```

Make the changes, then review and commit only the intended files:

```bash
git status
git diff
git add path/to/intended-file
git diff --cached
git commit -m "Describe the PX4 change"
```

Push the commit to the organization fork, not to `upstream`:

```bash
git push -u origin branch-name
```

The commit must be available in the organization fork before teammates can
clone the parent repository at that commit.

For PX4, avoid merging `upstream/main` unless you intentionally want to move
away from the project’s pinned PX4 version. The parent repository records a
specific PX4 commit, not merely the name of a branch.

## Update `frontier-explorer` after the submodule push

Once the updated submodule commit has been committed in
`frontier-explorer`, push the parent repository branch:

```bash
git push origin branch-name
```

Replace `branch-name` with the branch you are using in the parent repository.

The parent commit stores only the submodule’s commit ID. It does not copy the
submodule files into the parent repository.

Repeat the same two-stage process for another submodule by replacing the path,
repository name, and branch name.

## Update an existing checkout

After pulling a parent commit that changes a
submodule pointer:

```bash
git pull origin branch-name
git submodule update --init --recursive
```

Every teammate needs access to the organization repositories. HTTPS may prompt
for credentials when pushing changes.
