//bin/true; exec ruby -wx "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" lunch a-lunch
#!ruby

=begin

# Install

. ~/cbin/misc/completer-lunch.rb

=end

require_relative "completer"
using CompleterRefinements

def load_devices()
  lazy_list do
    %w(generic full bullhead angler marlin sailfish walleye taimen) \
        + read_file_lines("~/.android-devices").uniq
  end
end

def device_flavors
  lazy_list { load_devices.to_a.product(%w(eng userdebug)).map {|a,b| "#{a}-#{b}" } }
end

Completer.define do
  must device_flavors
end
