---
name: curated-pr
description: Keep the real Omarchy ZFS ISO PR branch clean by curating implementation changes from the full experimental branch.
---

# Curated PR Branch

Use this skill when preparing, reviewing, or updating the real ZFS ISO pull-request branch from the broader experimental ZFS work.

## Branches

- `feat/omarchy-zfs-iso` is the full working branch. It may contain skills, testing harness changes, notes, plans, debugging changes, and other development artifacts.
- `feat/omarchy-zfs-iso-pr` is the real PR branch. Keep it as clean as possible and limited to production implementation changes intended for review.

If a user mentions `feat/omarchy-zfs-is-pr`, treat it as a likely typo for `feat/omarchy-zfs-iso-pr` and confirm only if the exact branch name matters before running commands.

## Goal

Move only the real ZFS ISO implementation changes onto `feat/omarchy-zfs-iso-pr`. Do not bulk-merge or cherry-pick unrelated commits from `feat/omarchy-zfs-iso` unless the user explicitly asks for that.

## What Belongs In The PR Branch

- Installer implementation changes required for the ZFS ISO behavior.
- Minimal supporting config changes required by the installer path.
- Fixes that affect shipped ISO behavior.
- Tests only if they are explicitly intended to be part of the real PR and not just local validation tooling.

## What Usually Stays Off The PR Branch

- `.agents/skills/*` updates.
- `bin/omarchy-iso-vm-test` and local VM automation harness changes.
- README, plans, notes, debugging docs, or test-helper-only changes.
- Temporary instrumentation or local validation scaffolding.

## Workflow

Start from the curated branch:

```bash
git switch feat/omarchy-zfs-iso-pr
```

Inspect candidate changes from the full branch before applying them:

```bash
git diff feat/omarchy-zfs-iso-pr..feat/omarchy-zfs-iso -- configs/airootfs/root/.automated_script.sh
```

Prefer restoring specific files or hunks instead of merging the full branch:

```bash
git restore --source=feat/omarchy-zfs-iso -- configs/airootfs/root/.automated_script.sh
```

Before committing, verify the branch is scoped to intended implementation files only:

```bash
git status --short --branch
git diff --stat
git diff --check
bash -n configs/airootfs/root/.automated_script.sh
```

Review the diff carefully and avoid staging unrelated files:

```bash
git diff -- configs/airootfs/root/.automated_script.sh
git add -- configs/airootfs/root/.automated_script.sh
```

Commit only after confirming the staged diff is clean and focused:

```bash
git diff --cached --stat
git diff --cached --check
git commit -m "Fix ZFS PAM home unlocking"
```

## Current Context

The curated branch has been used to keep PAM/home-unlocking implementation work separate from the broader experimental branch. One example curated commit is:

```text
a49be68 Fix ZFS PAM home unlocking
```

That commit intentionally included only `configs/airootfs/root/.automated_script.sh`, not skills, VM test harness updates, or documentation-only artifacts.

## Review Rules

- Treat QEMU wired networking success as insufficient proof for real Wi-Fi/iwd installs.
- Avoid adding workaround config only because the manual ZFS installer bypasses Archinstall; note the installer debt instead unless a production fix is explicitly required.
- Remember the long-term direction: prepare ZFS pool, datasets, and mount tree, then use Archinstall with `pre_mounted_config` like the Btrfs path, followed by only ZFS-specific post-install work.
- Never push the curated branch unless the user explicitly asks.
