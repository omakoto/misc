: <<'COMMENT'

# Reenv

Reenv is a tool to capture the current shell environment
(environment, shell variables and functions) so that it
can be re-sourced later.

# Usage

TODO write it..

COMMENT

_reenv_base_file="$(mktemp --suffix reenv)"
_reenv_current="_reenv_base_file-cur"

function _reenv_clear() {
    _reenv_base_variables=()
    _reenv_base_functions=()
    rm -f "$_reenv_base_file"
}
_reenv_clear

# Dump all variables and functions
function _reenv_dump() {
    {
        compgen -v | while read -r name; do
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
    } | sort -z
}

# Capture the "base" environment.
function reenv-base() {
    # Capture all variable names.
    _reenv_base_variables=($(compgen -v | sort))
    _reenv_base_functions=($(compgen -A function | sort))

    # for n in "${_reenv_base_variables[@]}"; do
    #     echo "Var: $n"
    # done
    # for n in "${_reenv_base_functions[@]}"; do
    #     echo "Func: $n"
    # done

    _reenv_dump > "$_reenv_base_file"
}

# Dump the part of the current environment that has changed since
# reenv-base in a format that can be source'd later.
function reenv-cap() {
    if ! [[ -f "$_reenv_base_file" ]] ; then
        echo "Use reenv-base to capture the base line environment first!" 1>&2
        return 1
    fi

    _reenv_dump > "$_reenv_current"
    comm -13 -z "$_reenv_base_file" "$_reenv_current"

}



