#!/usr/bin/env ruby
=begin

Install a simple completion for a file,

# How to install.

. <(simplecomp.rb -e "$(cat <<'EOF'
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
EOF
)"  cat)

. <(simplecomp.rb -e '
#nofile  # This command does not take filenames
 -A, -e               : all processes
 -a                   : all with tty, except session leaders
  a                   : all with tty, including other users
 -d                   : all except session leaders
 -N, --deselect       : negate selection
  r                   : only running processes
  T                   : all processes on this terminal
  x                   : processes without controlling ttys
' ps)

=end

require_relative "completer"
using CompleterRefinements

Completer.define do
  # Initialize.
  flags = build_candidates extras
  take_files = !(extras =~ /^\#nofile/)

  # As long as the argument start with "-", flags are always
  # in the candidates.
  for_arg(/^-/) do
    option flags

    # If a command takes filenames, "--" will terminate the flag
    # parsing.
    if take_files
      option("--") {for_break}
    end
  end

  # The rest of the arguments are all filenames.
  if take_files
    for_arg do
      must take_file
    end
  end
end
