. <( exec ruby -wx "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" rg ~/cbin/rg-* )
: <<'__END_RUBY_CODE__'
#!ruby
def __END_RUBY_CODE__; end

=begin

# Install

. ~/cbin/misc/completer-rg.rb

ruby -x completer-rg.rb -c 1 rg

=end

require_relative "completer"
using CompleterRefinements

def gen_type_list
  lazy_list do
    %x(rg --type-list).split(/\n/).map do |x|
      type, desc = x.split(/\s* \: \s*/x, 2)
      type.as_candidate(help: desc)
    end
  end
end

Completer.define do
  maybe build_candidates("--type-list : Show all supported file types.") do
    finish
  end

  maybe build_candidates(%(
    -h  --help                              : Prints help information. Use --help for more details.
      )) do
    finish
  end

  for_arg(/^-/) do
    maybe build_candidates %(
    -s  --case-sensitive                    : Search case sensitively.
        --column                            : Show column numbers
    -c  --count                             : Only show count of matches for each file.
        --debug                             : Show debug messages.
        --files                             : Print each file that would be searched.
    -l  --files-with-matches                : Only show the paths with at least one match.
        --files-without-match               : Only show the paths that contains zero matches.
    -F  --fixed-strings                     : Treat the pattern as a literal string.
    -L  --follow                            : Follow symbolic links.
        --heading                           : Show matches grouped by each file.
        --hidden                            : Search hidden files and directories.
    -i  --ignore-case                       : Case insensitive search.
    -v  --invert-match                      : Invert matching.
    -n  --line-number                       : Show line numbers.
    -x  --line-regexp                       : Only show matches surrounded by line boundaries.
        --mmap                              : Searching using memory maps when possible.
        --no-filename                       : Never show the file name for a match.
        --no-heading                        : Don't group matches by each file.
        --no-ignore                         : Don't respect ignore files.
        --no-ignore-parent                  : Don't respect ignore files in parent directories.
        --no-ignore-vcs                     : Don't respect VCS ignore files
    -N  --no-line-number                    : Suppress line numbers.
        --no-messages                       : Suppress all error messages.
        --no-mmap                           : Never use memory maps.
    -0  --null                              : Print NUL byte after file names
    -o  --only-matching                     : Print only matched parts of a line.
    -p  --pretty                            : Alias for --color always --heading --line-number.
    -q  --quiet                             : Do not print anything to stdout.
    -S  --smart-case                        : Smart case search.
        --sort-files                        : Sort results by file path. Implies --threads=1.
    -a  --text                              : Search binary files as if they were text.

    -u  --unrestricted                      : Reduce the level of "smart" searching.
    -V  --version                           : Prints version information
        --vimgrep                           : Show results in vim compatible format.
    -H  --with-filename                     : Show file name for each match.
    -w  --word-regexp                       : Only show matches surrounded by word boundaries.
      )

    maybe build_candidates(%(
        --color                             : When to use color. [default: auto]
        )), %w(always never auto)

    # Flags that take no-completable arguments.
    maybe build_candidates(%(
        --color                             : When to use color. [default: auto]
        --colors                            : Configure color settings and styles.
        --context-separator                 : Set the context separator string. [default: --]
    -g  --glob                              : Include or exclude files/directories.
        --iglob                             : Include or exclude files/directories case insensitively.
        --path-separator                    : Path separator to use when printing file paths.
    -e  --regexp                            : Use pattern to search.
    -r  --replace                           : Replace matches with string given.
      )), []

    # Flags that takes a number.
    maybe build_candidates(%(
    -A  --after-context                     : Show NUM lines after each match.
    -B  --before-context                    : Show NUM lines before each match.
    -C  --context                           : Show NUM lines before and after each match.
    -M  --max-columns                       : Don't print lines longer than this limit in bytes.
    -m  --max-count                         : Limit the number of matches.
        --maxdepth                          : Descend at most NUM directories.
    -j  --threads                           : The approximate number of threads to use.
      )), take_number


    # Options that takes a size. Not supported yet; for now just take
    # a number.
    maybe build_candidates(%(
        --dfa-size-limit            : The upper size limit of the generated dfa.
        --max-filesize              : Ignore files larger than NUM in size.
        --regex-size-limit          : The upper size limit of the compiled regex.
      )), take_number

    # TODO Add more encodings.
    maybe build_candidates(%(
    -E  --encoding                          : Specify the text encoding of files to search.
      )), %w(utf-8)

    # Options that takes a type.
    maybe build_candidates(%(
    -t  --type                    : Only search files matching TYPE.
        --type-add                : Add a new glob for a file type.
        --type-clear              : Clear globs for given file type.
    -T  --type-not                : Do not search files matching TYPE.
      )), gen_type_list

    # Options that take a file.
    maybe build_candidates(%(
    -f  --file                       : Search for patterns from the given file.
        --ignore-file                : Specify additional ignore files.
      )), take_file

    maybe "--" do
      for_break
    end
  end

  # The rest are files only.
  for_arg do
    next_arg_must take_file
  end
end

__END_RUBY_CODE__
