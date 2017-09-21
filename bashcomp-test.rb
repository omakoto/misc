exec ruby -x "$0" -i -d cargo # for bash
#!ruby

require_relative "bashcomp"

def devices
  return %w(bullhead angler marlin sailfish walleye taimen)
end

def flavors
  return %w(userdebug eng)
end

def device_flavors
  ret = []
  devices.each {|d|
    flavors.each {|f|
      ret.push "#{d}-#{f}"
    }
  }
  return ret
end


BashComp.define { |cc|
  flags %w(-h --help -V --version --list -v --verbose -vv -q --quiet --frozen --locked)
  candidate "--other-flag"
  candidate { %w(aaa bbb) }
  # candidate devices
  candidate device_flavors
  # candidate "-V"
  # candidate "--help"
  # candidate "--version"

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
