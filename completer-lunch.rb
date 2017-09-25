exec ruby -x "$0" -i lunch a-lunch
#!ruby

# Completion for "lunch".

=begin

# Install
. <(~/cbin/misc/completer-lunch.rb)

export COMPLETER_DEBUG=/tmp/completer-debug.txt
unset COMPLETER_DEBUG

ruby -x completer-lunch.rb -i -d lunch

ruby -x completer-lunch.rb -i -p 1 -l "abcdef" -c 1 lunch </dev/null

ruby -x completer-lunch.rb -i -c 1 lunch bullhe </dev/null

=end

require_relative "completer"
using CompleterRefinements

def load_devices()
  devices = %w(generic full bullhead angler marlin sailfish walleye taimen)
  devices.push(* read_file_lines("~/.android-devices"))
  devices.uniq!
  return devices
end

def device_flavors
  ret = []
  load_devices.each {|d|
    %w(eng userdebug).each {|f|
      ret.push "#{d}-#{f}"
    }
  }
  return ret
end

Completer.define do
  # No state management, so just jump to the cursor word.
  to_cursor

  # Only the first argument gets completion.
  finish if cursor_index >= 2

  candidates device_flavors
end
