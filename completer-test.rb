exec ruby -x "$0" -i -d xxx
#!ruby

=begin

# Install
. <(~/cbin/misc/completer-test.rb)

ruby -x completer-test.rb -i -c 2 xxx --max

=end

require_relative "completer"

Completer.define do
  option "--file", arg_file
  option %w(--ignore-file --exclude), arg_file

  option "--threads", arg_number, arg_optional:true

  option "--max", arg_number

  option "--nice", arg_number(allow_negative:true)

  auto_state "--" do
    reset_state on_word: "--reset"

    candidates matched_files
  end
end
