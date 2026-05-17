: <<'COMMENT'

# Reenv

Reenv is a tool to capture the current shell environment
(environment, shell variables and functions) so that it
can be re-sourced later.

# Usage

TODO write it..

COMMENT

_reenv_file_base="${_reenv_file_base:-$(mktemp --suffix _reenv)}"
_reenv_file_current="${_reenv_file_current:-${_reenv_file_base}-cur}"

function _reenv_clear() {
    _reenv_base_variables=()
    _reenv_base_functions=()
    rm -f "$_reenv_file_base"
}
_reenv_clear

# Dump all variables and functions
function _reenv_dump() {
    {
        compgen -v | while read -r name; do
            # Skip certain variables
            if [[ "$name" =~ ^(BASH|FUNCNAME$|RANDOM$|SRANDOM$|EPOCHREALTIME$|EPOCHSECONDS$|SECONDS$|USER$|PWD$|_$) ]] ; then
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

# Capture the "base" environment.
function reenv-base() {
    # Capture all variable names.
    _reenv_base_variables=($(compgen -v | sort))
    _reenv_base_functions=($(compgen -A function | sort))

    _reenv_dump > "$_reenv_file_base"
}

# Dump the part of the current environment that has changed since
# reenv-base in a format that can be source'd later.
function reenv-cap() {
    if ! [[ -f "$_reenv_file_base" ]] ; then
        echo "Use reenv-base to capture the base line environment first!" 1>&2
        return 1
    fi

    _reenv_dump > "$_reenv_file_current"
    LC_ALL=C comm -13 -z "$_reenv_file_base" "$_reenv_file_current" | tr -d '\0'

    # TODO: Handle deletion
}



