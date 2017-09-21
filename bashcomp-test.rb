exec ruby -x "$0" -i -d cargo # for bash
#!ruby

require_relative "bashcomp"

# TODO How to define custom option?
# TODO State management?

def is_non_empty_dir(f)
  begin
    return File.directory?(f) && !Dir.empty?(f)
  rescue
    # Just ignore any errors.
    return false
  end
end

def file_completion(prefix)

  candidate "-h"
  candidate "-V"
  candidate "--help"
  candidate "--version"

  dir = prefix.sub(%r([^\/]*$), "") # Remove the last path section.

  StringIO.new(%x(command ls -dp1 #{shescape(dir)}* 2>/dev/null)).each_line { | f |
    f.chomp!

    # Do not add a space if it's a directory that's not empty.
    add_space = !is_non_empty_dir(f)
    candidate f, add_space
  }
end

define_completion { |cc|
  file_completion cc.current
}

# completion {
#   # The initial

#   # Flags won't change the state
#   flags %w(-h --help -V --version --list -v --verbose -vv -q --quiet --frozen --locked)

#   # option assumes one argument.
#   option "--explain", :no_completion

#   # the second argument can be a string array or a function.
#   option "--color", %w(auto always never)

#   option "--file", :file_completion

#   subcommand "help" {
#     any %w(build check clean doc new init run test bench update search publish install)
#   }

#   subcommand "cat" {
#     flags %w(-n -v)

#     files
#   }
# }
