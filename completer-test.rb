exec ruby -x "$0" -i -d xxx
#!ruby

=begin

# Install
. <(~/cbin/misc/completer-test.rb)

ruby -x completer-test.rb -i -c 2 xxx --max

__completer_context_passer | ruby -x completer-test.rb -i -c 1 xxx $ho

__completer_context_passer | ruby -x completer-test.rb -i -c 1 xxx $HO

=end

require_relative "completer"
using CompleterRefinements

Completer.define do
  option "--file", arg_file

  option %w(--ignore-file --exclude), arg_file

  option %w(--directory), arg_dir

  option "--image", arg_file("*.jpg")

  option "--threads", arg_number, arg_optional:true

  option "--max", arg_number

  option "--nice", arg_number(allow_negative:true)

  auto_state "--" do
    reset_state on_word: "--reset"

    candidates matched_files
  end

  auto_state "--always-test" do
    candidates %w[aaaa], always:true
  end
end
