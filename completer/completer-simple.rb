. <( exec ruby -wx "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" )
: <<'__END_RUBY_CODE__'
#!ruby
def __END_RUBY_CODE__; end

=begin

Install a simple completion for a file,

# How to install.

. completer-simple.rb -e '
  -A, --show-all           : equivalent to -vET
  -b, --number-nonblank    : number nonempty output lines, overrides -n
  -e                       : equivalent to -vE
  -E, --show-ends          : display $ at end of each line
  -n, --number             : number all output lines
  -s, --squeeze-blank      : suppress repeated empty output lines
  -t                       : equivalent to -vT
  -T, --show-tabs          : display TAB characters as ^I
  -u                       : (ignored)
  -v, --show-nonprinting   : use ^ and M- notation, except for LFD and TAB
      --help               : display this help and exit
      --version            : output version information and exit
' cat

. completer-simple.rb -e '
#nofile  # This command does not take filenames
 -A, -e               : all processes
 -a                   : all with tty, except session leaders
  a                   : all with tty, including other users
 -d                   : all except session leaders
 -N, --deselect       : negate selection
  r                   : only running processes
  T                   : all processes on this terminal
  x                   : processes without controlling ttys
' ps

=end

require_relative "completer"
using CompleterRefinements

Completer.define do
  flags = build_candidates extras
  take_files = !(extras =~ /^\#nofile/)

  for_arg(/^-/) do
    maybe flags

    if take_files
      maybe("--") do
        for_break
      end
    end
  end

  if take_files
    for_arg do
      next_arg_must take_file
    end
  end
end

__END_RUBY_CODE__
