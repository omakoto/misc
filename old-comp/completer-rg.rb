exec ruby -x "$0" -i rg ~/cbin/rg-*
#!ruby

=begin

Completion script for ripgrep.

. <(~/cbin/misc/completer-rg.rb) # Install

# Some test command lines...

export COMPLETER_DEBUG=/tmp/completer-debug.txt
unset COMPLETER_DEBUG

ruby -x completer-rg.rb -i -c 1 rg

ruby -x completer-rg.rb -i -c 1 rg --type-li
ruby -x completer-rg.rb -i -c 2 rg --type-list

ruby -x completer-rg.rb -i -c 2 rg --color

ruby -x completer-rg.rb -i -c 2 rg --type

ruby -x completer-rg.rb -i -c 2 rg --context

=end

require_relative "completer"
using CompleterRefinements

Completer.define do
  # Because the block is executed for each command line word
  # using "def" is not efficient.
  # cand_gen defines a method that takes care of the details.

  # Return the candidate list for "--type".
  cand_gen :rg_type_list do
    %x(rg --type-list).split(/\n/).map {|x| x.sub(/\:.*/, "")}
  end

  # Always allow filenames.
  # Technically the first non-flag argument should be a pattern,
  # but doesn't really matter much.
  candidate arg_file

  # Flags take no arguments.
  flags %w(
      -s  --case-sensitive
          --column
      -c  --count
          --debug
          --files
      -l  --files-with-matches
          --files-without-match
      -F  --fixed-strings
      -L  --follow
      -h  --help
          --heading
          --hidden
      -i  --ignore-case
      -v  --invert-match
      -n  --line-number
      -x  --line-regexp
          --mmap
          --no-filename
          --no-heading
          --no-ignore
          --no-ignore-parent
          --no-ignore-vcs
      -N  --no-line-number
          --no-messages
          --no-mmap
      -0  --null
      -o  --only-matching
      -p  --pretty
      -q  --quiet
      -S  --smart-case
          --sort-files
      -a  --text
      -u  --unrestricted
      -V  --version
          --vimgrep
      -H  --with-filename
      -w  --word-regexp
      )

  option "--color", %w(always never auto)

  # Options with non-completable arguments.
  option %w(
         --colors
         --context-separator
      -g --glob
         --iglob
         --path-separator
         --regexp
         --replace
      ) # , []  (i.e. no candidates) is implied.

  # Options that takes a number.
  option %w(
      -A --after-context
      -B --before-context
      -C --context
      -M --max-columns
      -m --max-count
         --maxdepth
      -j --threads
      ), arg_number

  # Options that takes a size. Not supported yet; for now just take
  # a number.
  option %w(
      --dfa-size-limit
      --max-filesize
      --regex-size-limit
      ), arg_number

  # TODO Add more encodings.
  option %w(--encoding), %w(utf-8)

  # Options that takes a type.
  option %w(
      --type
      --type-add
      --type-clear
      --type-not
      ), rg_type_list

  # Options that take a file.
  option %w(
      --file
      --ignore-file
      ), arg_file

  # After "--", only files are allowed.
  auto_state "--" do
    candidates matched_files
  end

  # --type-list is only allowed as the first option.
  candidate "--type-list" if cursor_index == 1

  # If --type-list is already in the command line, don't complete
  # further.
  finish if word == "--type-list"
end

=begin
    -s  --case-sensitive                    Search case sensitively.
        --column                            Show column numbers
    -c  --count                             Only show count of matches for each file.
        --debug                             Show debug messages.
        --files                             Print each file that would be searched.
    -l  --files-with-matches                Only show the paths with at least one match.
        --files-without-match               Only show the paths that contains zero matches.
    -F  --fixed-strings                     Treat the pattern as a literal string.
    -L  --follow                            Follow symbolic links.
    -h  --help                              Prints help information. Use --help for more details.
        --heading                           Show matches grouped by each file.
        --hidden                            Search hidden files and directories.
    -i  --ignore-case                       Case insensitive search.
    -v  --invert-match                      Invert matching.
    -n  --line-number                       Show line numbers.
    -x  --line-regexp                       Only show matches surrounded by line boundaries.
        --mmap                              Searching using memory maps when possible.
        --no-filename                       Never show the file name for a match.
        --no-heading                        Don't group matches by each file.
        --no-ignore                         Don't respect ignore files.
        --no-ignore-parent                  Don't respect ignore files in parent directories.
        --no-ignore-vcs                     Don't respect VCS ignore files
    -N  --no-line-number                    Suppress line numbers.
        --no-messages                       Suppress all error messages.
        --no-mmap                           Never use memory maps.
    -0  --null                              Print NUL byte after file names
    -o  --only-matching                     Print only matched parts of a line.
    -p  --pretty                            Alias for --color always --heading --line-number.
    -q  --quiet                             Do not print anything to stdout.
    -S  --smart-case                        Smart case search.
        --sort-files                        Sort results by file path. Implies --threads=1.
    -a  --text                              Search binary files as if they were text.
        --type-list                         Show all supported file types.
    -u  --unrestricted                      Reduce the level of "smart" searching.
    -V  --version                           Prints version information
        --vimgrep                           Show results in vim compatible format.
    -H  --with-filename                     Show file name for each match.
    -w  --word-regexp                       Only show matches surrounded by word boundaries.

    -f  --file <FILE>...                    Search for patterns from the given file.
        --ignore-file <FILE>...             Specify additional ignore files.

    -A  --after-context <NUM>               Show NUM lines after each match.
    -B  --before-context <NUM>              Show NUM lines before each match.
    -C  --context <NUM>                     Show NUM lines before and after each match.
    -M  --max-columns <NUM>                 Don't print lines longer than this limit in bytes.
    -m  --max-count <NUM>                   Limit the number of matches.
        --maxdepth <NUM>                    Descend at most NUM directories.
    -j  --threads <ARG>                     The approximate number of threads to use.

        --colors <SPEC>...                  Configure color settings and styles.
        --context-separator <SEPARATOR>     Set the context separator string. [default: --]
    -g  --glob <GLOB>...                    Include or exclude files/directories.
        --iglob <GLOB>...                   Include or exclude files/directories case insensitively.
        --path-separator <SEPARATOR>        Path separator to use when printing file paths.
    -e  --regexp <PATTERN>...               Use pattern to search.
    -r  --replace <ARG>                     Replace matches with string given.

        --dfa-size-limit <NUM+SUFFIX?>      The upper size limit of the generated dfa.
        --max-filesize <NUM+SUFFIX?>        Ignore files larger than NUM in size.
        --regex-size-limit <NUM+SUFFIX?>    The upper size limit of the compiled regex.

        --color <WHEN>                      When to use color. [default: auto]

    -E  --encoding <ENCODING>               Specify the text encoding of files to search.

    -t  --type <TYPE>...                    Only search files matching TYPE.
        --type-add <TYPE>...                Add a new glob for a file type.
        --type-clear <TYPE>...              Clear globs for given file type.
    -T  --type-not <TYPE>...                Do not search files matching TYPE.
=end

