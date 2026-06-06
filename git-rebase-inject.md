# git-rebase-inject Specification

`git-rebase-inject` is an interactive Git utility that allows you to select locally modified or untracked files and "inject" (squash/fixup) their changes into a chosen historical commit on your current branch.

---

## Workflow Specification

When `git-rebase-inject` is executed:

1. **Dirty Check**:
   - The script verifies if there are any uncommitted changes (modified, deleted, staged, or untracked/new files) by running `git status --porcelain`.
   - If no changes are found, the script prints "No uncommitted changes found." and exits.

2. **File Selection**:
   - The porcelain status list is presented to the user using `fzf` in multi-select mode:
     ```bash
     git status --porcelain | fzf --multi --prompt="Select files to inject: "
     ```
   - If the user cancels or selects no files, the script exits.

3. **Commit Selection**:
   - If files are selected, the script shows the Git commit history using `fzf` in single-selection mode.
   - Any arguments passed to `git-rebase-inject` (like branches, tags, or file paths) are forwarded to `git log`.
   - The `fzf` window divides the terminal, showing a preview pane at the top displaying `git show --stat -p` of the currently highlighted commit:
     ```bash
     --preview 'git show --stat -p --color=always {1}'
     --preview-window 'top:60%'
     ```
   - If the user cancels the commit selection, the script exits.

4. **Injection and Rebase**:
   - The script resolves the absolute paths of the selected files (using the repository root retrieved from `git rev-parse --show-toplevel`).
   - The selected files are staged:
     ```bash
     git add -- "${selected_files[@]}"
     ```
   - A temporary `fixup!` commit targeting the selected commit is created containing only the selected files:
     ```bash
     git commit --fixup="$target_commit" -- "${selected_files[@]}"
     ```
   - An autosquash rebase is performed non-interactively using `GIT_SEQUENCE_EDITOR=:`:
     - If the target commit has a parent, the base is `target_commit^`.
     - If the target commit is the root commit, the base is `--root`.
   - If the rebase fails (e.g. due to conflicts), the script exits with a helpful error message, keeping the repository in rebase state for the user to resolve or abort.

---

## Testing

> [!IMPORTANT]
> Always run the unit test script `git-rebase-inject_test.bash` after making any changes to `git-rebase-inject` to verify behavior.
