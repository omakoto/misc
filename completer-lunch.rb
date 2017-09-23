exec ruby -x "$0" -i -d lunch a-lunch
#!ruby

# Completion for "lunch".

=begin

# Install
. <(~/cbin/misc/completer-lunch.rb)

export COMPLETER_DEBUG=/tmp/completer-debug.txt
unset COMPLETER_DEBUG

ruby -x completer-lunch.rb -i -c 1 lunch

ruby -x completer-lunch.rb -i -c 1 lunch bullhe

=end

require_relative "completer"

def load_devices()
  devices = %w(generic full bullhead angler marlin sailfish walleye taimen)
  devices.push(* read_file_lines("~/.android-devices"))
  devices.uniq!
  return devices
end

Completer.define do
  # Only the first argument gets completion.
  finish if index > 2

  def device_flavors
    ret = []
    load_devices.each {|d|
      %w(eng userdebug).each {|f|
        ret.push "#{d}-#{f}"
      }
    }
    return ret
  end

  candidates device_flavors
end
