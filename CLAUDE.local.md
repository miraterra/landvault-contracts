# landvault-contracts — local configuration

Local, machine-independent configuration for CAGE coordination in this repo.
This file is `@`-included by `CLAUDE.md` and is tracked in git.

## Branching model

This repo uses a **trunk-based comb** off `main`: every issue branches off
`main`, takes its commits, and lands back into `main` via a `--no-ff` PR merge
before the next branch opens. There is no `staging` or `production` branch —
`main` is the single integration trunk.

**Current integration branch: `main`**

CAGE dispatch pre-flight bases new worktrees off this branch, and `cage-git
land` merges completed branches back into it.
