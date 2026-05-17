: <<'COMMENT'

# Reenv

Reenv tracks changes to the shell environment (variables and functions)
between two points in time and emits them as sourceable bash code.
This lets you capture environment changes made in one shell (or subshell)
and replay them in another.

# Usage

```bash
source /path/to/reenv.bash   # load the functions

reenv-base                   # snapshot the current environment as baseline
... make changes ...
reenv-cap                    # print everything that changed since reenv-base
```

The output of `reenv-cap` is valid bash: source it (or pipe it through bash)
to apply the same changes — including variable deletions and function changes —
to another shell.

# Examples

## Capture env changes and apply them in the same shell

```bash
source reenv.bash
reenv-base
export TOKEN="secret"
function greet() { echo "hello $1"; }
reenv-cap > /tmp/env-delta.sh

# Later, or in a new terminal:
source reenv.bash
source /tmp/env-delta.sh
# TOKEN and greet() are now set
```

## Propagate env changes made inside a subshell to the parent

```bash
source reenv.bash
reenv-base

(
    export BUILD_FLAGS="-O2 -DNDEBUG"
    unset DEBUG
    reenv-cap > /tmp/env-delta.sh
)

source /tmp/env-delta.sh
# BUILD_FLAGS is now set and DEBUG is unset in the current shell
```

## Use with a build or config script that modifies the environment

```bash
source reenv.bash
reenv-base
source ./setup-env.sh       # sets up PATH, exports, defines helpers
reenv-cap > /tmp/setup-delta.sh

# Share /tmp/setup-delta.sh so others can replay the same setup:
#   source /tmp/setup-delta.sh
```
COMMENT

_reenv_file_base="${_reenv_file_base:-$(mktemp --suffix _reenv)}"
_reenv_file_current="${_reenv_file_current:-${_reenv_file_base}-cur}"
_reenv_file_unset_base="${_reenv_file_unset_base:-$(mktemp --suffix _reenv)}"
_reenv_file_unset_current="${_reenv_file_unset_current:-${_reenv_file_unset_base}-cur}"

function _reenv_clear() {
    rm -f "$_reenv_file_base"*
    rm -f "$_reenv_file_unset_base"*
}
_reenv_clear


# Detect if a (variable) name should be skipped.
function _reenv_skip() {
    local name="$1"
    [[ "$name" =~ ^(BASH|FUNCNAME$|RANDOM$|SRANDOM$|EPOCHREALTIME$|EPOCHSECONDS$|SECONDS$|USER$|PWD$|_$) ]]
}

# Dump all variables and functions
function _reenv_dump() {
    {
        compgen -v | while read -r name; do
            # Skip certain variables
            if _reenv_skip "$name" ; then
                continue
            fi
            echo "#$name"
            declare -p "$name"
            echo -ne '\0'
        done

        # functions
        compgen -A function | while read -r name; do
            echo "#$name()"
            declare -f "$name"
            echo -ne '\0'
        done
    } | LC_ALL=C sort -z
}

# Dump all variables with `unset`. We use it to detect deleted entries.
function _reenv_dump_unset() {
    {
        compgen -v | while read -r name; do
            if _reenv_skip "$name" ; then
                continue
            fi
            # Use double quotes just so it's easier to write the expected
            # text in tests.
            printf "unset -v \"%s\"\n\0" "$name"
        done

        # functions
        compgen -A function | while read -r name; do
            printf "unset -f \"%s\"\n\0" "$name"
        done
    } | LC_ALL=C sort -z
}

# Capture the "base" environment.
function reenv-base() {
    _reenv_dump > "$_reenv_file_base"
    _reenv_dump_unset > "$_reenv_file_unset_base"
}

# Dump the part of the current environment that has changed since
# reenv-base in a format that can be source'd later.
function reenv-cap() {
    if ! [[ -f "$_reenv_file_base" ]] ; then
        echo "Use reenv-base to capture the base line environment first!" 1>&2
        return 1
    fi

    _reenv_dump > "$_reenv_file_current"
    _reenv_dump_unset > "$_reenv_file_unset_current"

    # Dump deleted variables and functions with `unset`.
    LC_ALL=C comm -23 -z "$_reenv_file_unset_base" "$_reenv_file_unset_current" | tr -d '\0'

    # Dump added or changed variables and functions
    LC_ALL=C comm -13 -z "$_reenv_file_base" "$_reenv_file_current" | tr -d '\0'
}



