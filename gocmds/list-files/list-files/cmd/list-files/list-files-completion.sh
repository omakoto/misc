# list-files-completion.sh - Bash completion script for list-files.
# This script enables tab completion for options and arguments of list-files.

_list_files_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-a --show-all -d --show-directories -F --show-fullpath -h --help --home-tild --no-home-tild -j --para -m --max-depth -n --max-files --no-show-fullpath --no-show-relative-path --no-strip-start-dir -r --reverse -R --show-relative-path --strip-start-dir --colors --bash-completion"

    case "$prev" in
        --colors)
            COMPREPLY=( $(compgen -W "always never auto" -- "$cur") )
            return 0
            ;;
        -j|--para|-m|--max-depth|-n|--max-files)
            # These expect numeric values
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    else
        # Fall back to standard file and directory completion
        COMPREPLY=( $(compgen -f -- "$cur") )
    fi
}
complete -F _list_files_completion list-files
