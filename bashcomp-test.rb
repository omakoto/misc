# ruby script \
. <(bashcomp.rb -d -i cargo <<'RUBY_END'
#line 4

# TODO How to define custom option?
# TODO State management?



def no_completion()
end

def file_completion(prefix)

  candidate "aaa"
  candidate "bbb"
  candidate "ccc"

  StringIO.new(%x(command ls -dp1 #{shescape(prefix)}* 2>/dev/null)).each_line { | line |
    candidate line
  }
end

file_completion $cc.current

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

RUBY_END
)
