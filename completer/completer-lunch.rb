//bin/true; exec ruby -x "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" lunch a-lunch
#!ruby

=begin

# Install

. ~/cbin/misc/completer-lunch.rb

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
  lazy_list do
    ret = []
    load_devices.each {|d|
      %w(eng userdebug).each {|f|
        ret.push "#{d}-#{f}"
      }
    }
    next ret
  end
end

Completer.define do
  must device_flavors
end
