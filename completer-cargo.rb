exec ruby -x "$0" -i -d cargo # for bash
#!ruby

require_relative "completer"

# def devices
#   return %w(bullhead angler marlin sailfish walleye taimen)
# end

# def flavors
#   return %w(userdebug eng)
# end

# def device_flavors
#   ret = []
#   devices.each {|d|
#     flavors.each {|f|
#       ret.push "#{d}-#{f}"
#     }
#   }
#   return ret
# end

subcommands = %w(build check clean doc new init run test bench update search publish install)

Completer.define do
  def take_colors()
    option "--colors", %w(auto always never)
  end

  # "flags" is just an alias to "candidates".
  flags %w(-h --help -V --version --list -v --verbose -vv -q --quiet --frozen --locked)
  candidates "help"
  candidates subcommands

  take_files

  # After "--", only files are allowed.
  auto_state "--" do
    take_files
  end

  auto_state "help" do
    next_state EMPTY if word(-2) == "help"

    candidates subcommands
  end

  auto_state "build" do
    flags %w(-h --help --all --lib --bins --tests --benches --release --all-features --no-default-features -v --verbose -q --quiet --frozen --locked)

    take_colors

# -p SPEC
# --package SPEC ...
# --exclude SPEC ...
# -j N
# --jobs N
# --bin NAME
# --example NAME
# --examples
# --test NAME
# --bench NAME
# --features FEATURES
# --target TRIPLE
# --manifest-path PATH
# --color WHEN
# --message-format FMT

  end
end
