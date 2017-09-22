exec ruby -x "$0" -i -d lunch a-lunch # for bash
#!ruby

# Completion for "lunch".

require_relative "completer"

Completer.define do
  # Only the first argument gets completion.
  finish if index > 2

  def load_devices()
    devices = %w(generic full bullhead angler marlin sailfish walleye taimen)
    devices.push(* read_file_lines("#{ENV['HOME']}/.android-devices"))
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

  candidates device_flavors
end
