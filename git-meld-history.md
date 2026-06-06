# git-meld-history Specification

`git-meld-history` is a command-line tool that lets you interactively browse a repository's Git commit history using `fzf` and visually diff selections (either a single commit, a range of commits, or commit-to-workspace comparisons) using `git-meld`.

---

## Workspace Comparison (CURRENT) Spec

When `git-meld-history` is executed:
1. **Dirty Directory Check**:
   - The script checks if the repository has any local changes (staged, unstaged, or untracked/new files) by running `git status --porcelain`.
   - If changes are detected, a fake commit labeled `(CURRENT) Local changes` is prepended to the top of the `fzf` history list.

2. **Solo Selection**:
   - Selecting **only** `(CURRENT)` compares `HEAD` against the current workspace.
   - To ensure new/untracked files are displayed in the diff, the script retrieves untracked files using `git ls-files -z --others --exclude-standard`, registers them with intent-to-add status (`git add -N`), triggers `git meld HEAD`, and then resets the index (`git reset HEAD`) to revert the index back to its clean state once the background comparison directories have been populated.

3. **Multi-Selection**:
   - Selecting `(CURRENT)` alongside other historical commits compares the **oldest selected commit** to the current workspace.
   - The script filters out `(CURRENT)` to parse the chronological oldest commit using `git log --no-walk --date-order --reverse --format="%H"`.
   - Just like solo selection, untracked files are staged with `git add -N`, `git meld <oldest>` is called, and the index is restored with `git reset HEAD`.

4. **Pure Historical Selections**:
   - If `(CURRENT)` is not selected, the script falls back to standard historical comparisons (either single commit parent-to-child or range comparisons from the oldest to newest selected commits).
