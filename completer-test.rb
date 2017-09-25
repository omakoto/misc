exec ruby -x "$0" -i -d xxx
#!ruby

=begin

# Install
. <(~/cbin/misc/completer-test.rb)

__completer_context_passer | ruby -x completer-test.rb -i -c 2 xxx --max

__completer_context_passer | ruby -x completer-test.rb -i -c 1 xxx '$ho'

__completer_context_passer | ruby -x completer-test.rb -i -c 1 xxx '$HO'

__completer_context_passer | ruby -x completer-test.rb -i -c 3 xxx --end \<

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

    candidate "--reset"
    candidates matched_files
  end

  # After --end, no completion.
  auto_state "--end" do
    finish
  end

  auto_state "--always-test" do
    candidates %w[aaaa], always:true
  end

  add_state "state-a", on_word:"tostatea" do
    candidates "aaa"
  end

  add_state "state-b", on_word:["XXX", "YYY"] do
    candidates "bbb"
  end

  add_state "state-c", on_word:/^STATEC/ do
    candidates "ccc"
  end

  next_state "state-a", on_word: "ns-statea"

  next_state "state-b", on_word: ["ns-stateb"]

  next_state "state-c", on_word: /^ns-statec/
end
