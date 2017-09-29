. <( exec ruby -wx "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" rg ~/cbin/rg-* )
: <<'__END_RUBY_CODE__'
#!ruby
def __END_RUBY_CODE__; end

=begin

# Install

. ~/cbin/misc/completer-rg.rb

=end

require_relative "completer"
using CompleterRefinements

def gen_type_list
  lazy do
    %x(rg --type-list).split(/\n/).map {|x| x.sub(/\:.*/, "")}
  end
end

Completer.define do
  maybe "--type-list" do
    candidates gen_type_list
    finish
  end

  maybe %w(-h --help) do
    finish
  end

  for_arg(/^-/) do
    maybe words %(
      # -s  --case-sensitive
      #     --column
      -c  --count
      #     --debug
          --files
      -l  --files-with-matches
          --files-without-match
      -F  --fixed-strings
      -L  --follow
      #     --heading
          --hidden
      -i  --ignore-case
      -v  --invert-match
      -n  --line-number
      # -x  --line-regexp
      #     --mmap
      #     --no-filename
      #     --no-heading
      #     --no-ignore
      #     --no-ignore-parent
      #     --no-ignore-vcs
      # -N  --no-line-number
      #     --no-messages
      #     --no-mmap
      # -0  --null
      # -o  --only-matching
      # -p  --pretty
      # -q  --quiet
      # -S  --smart-case
      #     --sort-files
      # -a  --text
      # -u  --unrestricted
      # -V  --version
      #     --vimgrep
      # -H  --with-filename
      # -w  --word-regexp
      )

    maybe "--color", %w(always never auto)

    # Flags that take no-completable arguments.
    maybe words(%(
      #    --colors
      #    --context-separator
      # -g --glob
      #    --iglob
      #    --path-separator
      #    --regexp
      #    --replace
      )), []

    # Flags that takes a number.
    maybe words(%(
      -A --after-context
      -B --before-context
      -C --context
      # -M --max-columns
      -m --max-count
         --maxdepth
      # -j --threads
      )), take_number


    # Options that takes a size. Not supported yet; for now just take
    # a number.
    maybe words(%(
      # --dfa-size-limit
      --max-filesize
      # --regex-size-limit
      )), take_number

    # TODO Add more encodings.
    maybe %w(--encoding), %w(utf-8)

    # Options that takes a type.
    maybe words(%(
      --type
      --type-add
      --type-clear
      --type-not
      )), gen_type_list

    # Options that take a file.
    maybe words(%(
      --file
      --ignore-file
      )), take_file

    maybe "--" do
      for_break
    end
  end

  # The rest are files only.
  for_arg do
    next_arg_must take_file
  end
end

__END_RUBY_CODE__
