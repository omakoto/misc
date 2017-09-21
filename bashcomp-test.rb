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

# TODO Defining states should be done at the beginning, but transition should be based on the current context.
# i.e. nested states should still be registered at the beginning but transition should only happen
# when finding the word in the right context.

BashComp.define do
  # Define it implicitly.
  # "auto_transition: false" means "end" is just a state name, and
  # won't automatically transition to this state when seeing the word
  # "end".
  state "end", auto_transition: false do
    # No completion is available.
  end

  # Root commands are implicitly applied to the "start" state.

  # "flags" is just an alias to "candidate".
  flags %w(-h --help -V --version --list -v --verbose -vv -q --quiet --frozen --locked)
  candidates "--single-candidate"
  candidates { %w(aaa bbb) }
  # candidate devices

  # option:
  # - Add the first arg to the flag set
  # - If the previous word is the first arg, then use the second arg for the
  #   completion of the current word.
  #   optional:true means also all the other options are enabled.
  option "--flavor", device_flavors, optional:false

  # Take files.
  allow_files

  # This is equivalent to:
  # define state "state".
  # to_state "--" if word[i] == "--"
  state "--" do
    allow_files
  end

  state "help" do
    # candidate %w(build check clean doc new init run test bench update search publish install)

    to_sate "empty" if cc.word(-2) == "help"

    # TODO: Move to the "end" state.
  end


  # file_completion cc.current
end

# completion {
#   # The initial state

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
