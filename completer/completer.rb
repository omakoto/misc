#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'pathname'
require 'singleton'
require 'json'
require 'pp'

require 'rubygems' # For version check on<1.9
abort "#{$0.sub(/^.*\//, "")} requires ruby >= 2.4" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4')

=begin
- To enable debug output, use:

export COMPLETER_DEBUG=1

TODO:

- There seems to be a bash bug when completing the same command line twice
in a row, the first one got no candidates, and the second one got one.
This breaks FZF completion.
Figure out a workaround.

See:
https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html#Programmable-Completion
https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html#Programmable-Completion

- Test -e option
- Zsh parameter description not working properly. -X seems to be a wrong option.

=end

# Whether to enable debug or not.
DEBUG = (ENV['COMPLETER_DEBUG'] == "1")

# Whether completion is being performed in case-insensitive mode.
IGNORE_CASE = (ENV['COMPLETER_IGNORE_CASE'] == "1")

# If a completion happens for the same command in a row within this many seconds,
# we reuse the last result.
# Set "-1" to disable cache.
CACHE_TIMEOUT = (ENV['COMPLETER_CACHE_TIMEOUT'] || 5).to_f

# Note FZF doesn't seem to work well on zsh.

# Whether always use FZF or not.
ALWAYS_FZF = (ENV['COMPLETER_ALWAYS_FZF'] == "1")

# If a completion happens for the same command in a row within this many seconds,
# we reuse the last result, and use FZF.
# Set "-1" to disable cache.
AUTO_FZF_TIMEOUT = (ENV['COMPLETER_FZF_TIMEOUT'] || 1.5).to_f

# Data files and debug log goes to this directory.
APP_DIR = Dir.home + "/.completer/"
Dir.exist?(APP_DIR) or FileUtils.mkdir_p(APP_DIR)

# Debug output goes to this file.
DEBUG_FILE = APP_DIR + "/completer-debug.txt"

$debug_indent_level = 0
$_cached_shell = nil
$debug_out= nil

RAW_MARKER = "\e"
HELP_MARKER = "\t"
INCOMPLETE_MARKER = "\b"

module CompleterRefinements
  refine Kernel do
    # Debug print.
    def debug(*args, &b)
      return false unless DEBUG

      if args.length > 0
        msg = args.join("\n").gsub(/^/m, "  " * $debug_indent_level + "D:").chomp

        # If stdout is TTY, assume the script is executed directly for
        # testing, and write log to stderr.
        if $stdout.tty?
          $stderr.puts msg
        else
          $debug_out = ($debug_out or open(DEBUG_FILE, "w"))
          $debug_out.puts msg
          $debug_out.flush
        end
      end
      debug(b.call()) if b
      return true
    end

    def debug_indent(&block)
      $debug_indent_level += 1

      if block
        begin
          block.call()
        ensure
          $debug_indent_level -= 1
        end
      end
    end

    def debug_unindent()
      $debug_indent_level -= 1
    end

    def die(*msg)
      abort "#{__FILE__}: " + msg.join("") + "\n" + caller.map{|x|x.to_s}.join("\n")
    end

    # Shell-escape a single token; basic "bourne" version.
    def bourne_shescape(arg)
      if arg =~ /[^a-zA-Z0-9\-\.\_\/\:\+\@]/
          return "'" + arg.gsub(/'/, "'\\\\''") + "'"
      else
          return arg;
      end
    end

    # Shell-unescape a single token; basic "bourne" version.
    def bourne_unshescape(arg)
      if arg !~ /[\'\"\\]/
        return arg
      end

      ret = ""
      pos = 0
      while pos < arg.length
        ch = arg[pos]

        case ch
        when "'"
          pos += 1
          while pos < arg.length
            ch = arg[pos]
            pos += 1
            if ch == "'"
              break
            end
            ret += ch
          end
        when '"'
          pos += 1
          while pos < arg.length
            ch = arg[pos]
            pos += 1
            if ch == '"'
              break
            elsif ch == '\\'
              if pos < arg.length
               ret += arg[pos]
              end
              pos += 1
            end
            ret += ch
          end
        when '\\'
          pos += 1
          if pos < arg.length
            ret += arg[pos]
            pos += 1
          end
        else
          ret += ch
          pos += 1
        end
      end

      return ret
    end

    def shescape(arg)
      get_shell.shescape(arg)
    end

    def unshescape(arg)
      get_shell.unshescape(arg)
    end

    def get_shell()
      return $_cached_shell if $_cached_shell

      $_cached_shell = (-> {
        shell_name = ENV["SHELL"].sub(/^.*\//, "")
        case shell_name
        when "bash"
          debug "Shell is bash."
          return BashAgent.new
        when "zsh"
          debug "Shell is zsh."
          return ZshAgent.new
        else
          die "Unsupported shell '#{shell_name}'"
        end
      }).call
    end

    # Takes a String or a Candidate and return as a Candidate.
    def as_candidate(value, raw:nil, completed: nil, help: nil)
      if value.instance_of? Candidate
        return value
      elsif value.instance_of? String
        # If a string contains a TAB, the following section is a
        # help string.
        (candidate, s_help) = value.split(HELP_MARKER, 2)

        # If a candidate starts with an ESC, it's a raw candidate.
        s_raw = candidate.sub!(/^#{RAW_MARKER}/o, "") ? true : false

        # If a candidate ends with a BS, it's not a completed
        # candidate.
        s_completed = candidate.sub!(/#{INCOMPLETE_MARKER}$/, "") ? false : true

        # If one is provided as an argument, use it.
        raw = s_raw if raw == nil
        completed = s_completed if completed == nil
        help = s_help if help == nil

        return Candidate.new(candidate, raw:raw, completed:completed, help:help)
      else
        return nil
      end
    end

    # Takes a block that generates a list. The block will be executed only when
    # needed.
    def lazy_list(&block)
      return LazyList.new(&block)
    end

    # This is basically same as %w(...), except it treats # as comments.
    def words(*args)
      ret = []
      args.each do |arg|
        arg.split(/\n/).each do |line|
          l = line.sub(/^\s+/, "").sub(/\s*\#.*/, "")
          if l.length > 0
            l.split(/\s+/).each do |word|
              ret << word
            end
          end
        end
      end
      return ret
    end

    def build_candidates(*args)
      ret = []
      args.each do |arg|
        arg.split(/\n/).each do |line|
          # Remove leading spaces and comments.
          l = line.sub(/^\s+/, "").sub(/\s* \# .*/x, "")

          # : will separate flags and helps
          l, help = l.split(/\s* : \s*/x, 2)

          # flags are separated by spaces or commas.
          if l != nil && l.length > 0
            l.split(/[\s\,]+/).each do |word|
              next if word.length == 0
              ret << word.as_candidate(help:help)
            end
          end
        end
      end
      return ret
    end
  end # refine Kernel

  refine String do
    # When a string starts with "~/", then expand to the home directory.
    # Doesn't support ~USERNAME/.
    def expand_home()
      return self.sub(/^~\//, "#{Dir.home}/")
    end

    # Same as self.start_with?(prefix), except it does case-insensitive
    # comparison when needed.
    def has_prefix?(prefix)
      return true unless prefix
      if IGNORE_CASE
        return self.downcase.start_with? prefix.downcase
      else
        return self.start_with? prefix
      end
    end

    # Build a candidate from a String.
    def as_candidate(raw:nil, completed: nil, help: nil)
      return Kernel.as_candidate(self, raw:raw, completed:completed, help:help)
    end
  end # refine String
end

class LazyList
  include Enumerable

  def initialize(&block)
    block or die "block must be provided."
    @block = block
    @list = nil
  end

  def each(&block)
    @list = @block.call() unless @list
    @list.each(&block)
  end
end

using CompleterRefinements

#===============================================================================
# Helpers
#===============================================================================
module CompleterHelper
  # Return true if a given path is a directory and not empty.
  def is_non_empty_dir(f, ignore_files: false)
    begin
      return false unless File.directory?(f)

      if ignore_files
        return f.children.any? { |x| x.directory? }
      else
        return !Dir.empty?(f)
      end
    rescue SystemCallError => e
      debug {"is_non_empty_dir(): #{e.inspect}"}
      # Just ignore any errors.
      return false
    end
  end

  # Find matching files for a given prefix, with a mask.
  def get_matched_files(prefix, wildcard = "*")
    # Remove the last path component.
    dir = prefix.sub(%r([^\/]*$), "")

    debug {"prefix=#{prefix} dir=#{dir} wildcard=#{wildcard}"}

    if dir != "" and !Dir.exist? dir
      return
    end

    ret = []

    flag = File::FNM_DOTMATCH
    if IGNORE_CASE
      flag |= File::FNM_CASEFOLD
    end

    begin
      Pathname.new(dir == "" ? "." : dir).children.each do |path|
        if path.directory?
          cand = path.to_s
          cand += "/"
          cand += INCOMPLETE_MARKER if is_non_empty_dir(path)
        else
          # If it's a file, only add when the basename matches wildcard.
          next unless File.fnmatch(wildcard, path.basename, flag)
          cand = path.to_s
        end
        ret.push(cand)
      end
    rescue SystemCallError => e
      debug {"get_matched_files(): #{e.inspect}"}
    end

    return ret
  end

  # Find matching directories for a given prefix.
  def get_matched_dirs(prefix)
    # Remove the last path component.
    dir = prefix.sub(%r([^\/]*$), "")

    if dir != "" and !Dir.exists? dir
      return
    end

    ret = []

    begin
      Pathname.new(dir == "" ? "." : dir).children.each do |path|
        next unless path.directory?
        cand = path.to_s
        cand += "/"
        cand += INCOMPLETE_MARKER if is_non_empty_dir(path, ignore_files:true)
        ret.push(cand)
      end
    rescue SystemCallError => e
      debug {"get_matched_dirs(): #{e.inspect}"}
    end

    return ret
  end

  # Read all lines from a file, if exists.
  def read_file_lines(file, ignore_comments:true)
    file = file.expand_home
    ret = (File.exist? file) ? open(file, "r").read.split(/\n/) : []

    if ignore_comments
      ret = ret.reject {|x| x =~/^\#/ }
    end

    return ret;
  end

  # Accept an integer.
  def get_matched_numbers(prefix, allow_negative:false)
    lazy_list do
      if allow_negative
        next [] unless prefix =~ /^\-?\d*$/
      else
        next [] unless prefix =~ /^\d*$/
      end

      if prefix == ""
        if allow_negative
          next ["-1".."-9", "0".."9"]
        else
          next ["0".."9"]
        end
      else
        next ("0".."9").map {|x| prefix + x }
      end
    end
  end

  def take_file(wildcard="*")
    lazy_list { get_matched_files arg, wildcard }
  end

  def take_dir()
    lazy_list { get_matched_dirs arg }
  end

  def take_number(allow_negative:false)
    lazy_list { get_matched_numbers arg, allow_negative:allow_negative }
  end
end

#===============================================================================
# Class to store the information from the previous invocation.
#===============================================================================
class Store
  include Singleton

  STORE_FILE = APP_DIR + "last_session.json"

  def initialize
    @values = {}

    if File.exist? STORE_FILE
      @values = JSON.parse(open(STORE_FILE, "r").read)
    end
  end

  def save()
    open(STORE_FILE, "w").write(JSON.generate(@values))
  end

  def get(key, default=nil)
    return @values.fetch(key, default)
  end

  def set(key, value)
    @values[key] = value
  end
end

#===============================================================================
# Candidate
#===============================================================================

# Represents a single candidate.
class Candidate
  using CompleterRefinements

  def initialize(value, raw:false, completed: true, help: "")
    value or die "Empty candidate detected."

    @value = value.chomp
    @raw= raw
    @completed = completed
    @help = help == "" ? nil : help
  end

  # The candidate text.
  attr_reader :value

  # Raw candidates will not be escaped.
  attr_reader :raw

  # When a candidate is "completed", it's not a prefix of another text.
  # A completed candidate will be followed by a space when expanded.
  attr_reader :completed

  # Help text, bash can't show it, but maybe zsh can.
  attr_reader :help

  # Whether a candidate has a prefix or not.
  def has_prefix?(prefix)
    return @value.has_prefix?(prefix)
  end

  def as_candidate()
    return self
  end

  def to_s()
    return "{Candidate:value=#{shescape value}#{raw ? " [raw]" : ""}" +
        "#{completed ? " [completed]" : ""}" +
        "#{help ? " " + help : ""}}"
  end

  def to_parsable()
    ret = ""
    ret << RAW_MARKER if raw
    ret << value
    ret << INCOMPLETE_MARKER unless completed
    if help
      ret << HELP_MARKER
      ret << help
    end
    return ret
  end
end

class CandidateCache
  include Singleton

  STORE_FILE = APP_DIR + "last_candidates.dat"

  def initialize
  end

  def save(candidates)
    open(STORE_FILE, "w") do |out|
      candidates.each do |c|
        out.puts c.to_parsable
      end
    end
  end

  def load()
    return [] unless File.exist? STORE_FILE

    ret = []
    open(STORE_FILE, "r").each_line do |line|
      line.chomp!
      ret << line.chomp.as_candidate
    end
    return ret
  end
end

#===============================================================================
# Shell interface
#===============================================================================

class BasicShellAgent
  def initialize()
    # Shell and environmental variables.
    @env = {}
    @jobs = []
  end

  attr_reader :env, :jobs

  def shescape(arg)
    bourne_shescape arg
  end

  def unshescape(arg)
    bourne_unshescape arg
  end

  def install(commands, script, extras)
    die "install() must be overridden."
  end

  def add_candidate(candidate)
    die "add_candidate() must be overridden."
  end

  def start_completion()
  end

  def end_completion()
  end

  def maybe_override_candidates(engine)
    # Nothing to do
  end

  def variable_completable?(arg)
    # Assume variables start with "$"
    return (arg =~ /^\$([a-z0-9\_]*)$/i) ? $1 : nil
  end

  def variable_expandable?(arg)
    # Assume variables start with "$"
    return (arg =~ /^\$([a-z0-9\_]*)\/$/i) ? $1 : nil
  end
end


class BashAgent < BasicShellAgent
  SECTION_SEPARATOR = "\n-*-*-*-COMPLETER-*-*-*-\n"

  def fzf_supported()
    return true
  end

  def install(commands, script, extras)
    command = commands[0]
    func = "_#{command.gsub(/[^a-z0-9]/i) {|c| "_" + c.ord.to_s(16)}}_completion"

    debug {"Installing completion for '#{command}', function='#{func}'"}

    script_file = File.expand_path $0

    extra_option = (extras == nil or extras == "") ? "" : "-e #{shescape extras}"

    # Note, we generate "COMPREPLY=(" and ")" by code too, which will
    # allow us to execute any code from the script if needed.
    puts <<~EOF
        # Map [TAB] to "toggle overwrite-mode twice, then complete".
        # This will run a completion *after resetting the context*.
        # Normally, when the user does a completion twice in a row
        # on the same command line, readline switches to the
        # "show matched candidates, but don't insert to the command line"
        # mode. This wouldn't work well with FZF -- if the user cancels
        # on FZF first, then hit TAB again, readline would fall into
        # this mode, and the result from the second FZF invocation
        # wouldn't be inserted into command line.
        #
        # The following keybindings fixes it.
        bind '"\\ecp1": overwrite-mode'
        bind '"\\ecp2": complete'
        bind '"\\C-i": "\\ecp1\\ecp1\\ecp2"'

        # This feeds information within shell (e.g. shell variables)
        # to completer.
        function __completer_context_passer {
            declare -p
            echo -n "#{SECTION_SEPARATOR}"
            jobs
        }

        # Actual completion function.
        function #{func} {
          export COMP_POINT
          export COMP_LINE
          export COMP_TYPE
          . <( __completer_context_passer |
              ruby -x "#{script_file}" #{extra_option} \
                  -c "$COMP_CWORD" "${COMP_WORDS[@]}" \
                  )
        }
        EOF

    commands.each do |c|
      puts "complete -o nospace -F #{func} -- #{c}"
    end
  end

  # Called when completion is about to start.
  def start_completion()
    # Parse output from __completer_context_passer and extract
    # variables and jobs.
    # If STDIN is tty, just skip it, which is handy when debugging.
    if !$stdin.tty?
      debug_indent do
        vars, jobs = $stdin.read.split(SECTION_SEPARATOR)
        vars and vars.split(/\n/).each do |line|
          if line =~ /^declare\s+(\S+)\s+([^=]+)\=(.*)$/ then
            flag, name, value = $1, $2, $3
            debug {"#{flag}: #{name} = #{value}"}
            next if flag =~ /[aA]/ # Ignore arrays and hashes
            @env[name] = unshescape value
          end
        end

        # TODO Parse jobs
        jobs = jobs # suppress warning.
      end
    end

    puts <<~EOF
          local IFS=$'\\n'; COMPREPLY=(
        EOF
  end

  def end_completion()
    puts <<~EOF
          ) # END COMPREPLY
        EOF
  end

  def maybe_override_candidates(engine)
    do_filename_completion = false
    1.upto(engine.cursor_index - 1).each do |i|
      # When there's an unquoted redirect marker, do a filename completion.
      arg = engine.orig_args[i]
      if arg =~ /^[\<\>]/
        do_filename_completion = true
      end
    end
    if do_filename_completion
      engine.candidates engine.get_matched_files engine.cursor_arg
    end
  end

  # Return as a candidate string for bash.
  # Note bash can't show a help string.
  def add_candidate(candidate)
    s = shescape(candidate.value)
    s += " " if candidate.completed

    # Output will be eval'ed, so need double-escaping unless raw.
    out = candidate.raw ? s : shescape(s)
    debug out
    puts out
  end
end

=begin
Interface for Zsh.
See:
http://www.csse.uwa.edu.au/programming/linux/zsh-doc/zsh_23.html
https://linux.die.net/man/1/zshcompsys
http://zsh.sourceforge.net/Guide/zshguide06.html
https://linux.die.net/man/1/zshcompwid (for compadd command)

Note zsh always seems to do variable expansions, so we don't have to do it.

=end
class ZshAgent < BasicShellAgent
  def fzf_supported()
    return false # FZF doesn't seem to work well in the zsh completion context.
  end

  def install(commands, script, extras)

    command = commands[0]
    func = "_#{command.gsub(/[^a-z0-9]/i) {|c| "_" + c.ord.to_s(16)}}_completion"

    debug {"Installing zsh completion for '#{command}', function='#{func}'"}

    script_file = File.expand_path $0

    extra_option = (extras == nil or extras == "") ? "" : "-e #{shescape extras}"

    puts <<~EOF
        function #{func} {
          . <(ruby -x "#{script_file}" #{extra_option} \
                  -c "$(( $CURRENT - 1 ))" "${words[@]}" \
                  )
        }
        EOF

    commands.each do |c|
      puts "compdef #{func} #{c}"
    end
  end

  def add_candidate(candidate)
    s = shescape(candidate.value)
    s += " " if candidate.completed

    # -S '' tells zsh not to add a space afterward. (because we do it by ourselves.)
    # -Q prevents zsh from quoting metacharacters in the results, which we do too.
    # -f treats the result as filenames.
    # -X description -> TODO This seems to be a wrong flag to use.
    # -U suppress filtering by zsh
    descopt = candidate.help ? "-X #{shescape candidate.help}" : ""

    fileopt = File.exist?(s) ? "-f" : ""

    # Need -Q to make zsh preserve the last space.
    out = "compadd -S '' -Q -U #{descopt} #{fileopt} -- #{(candidate.raw ? s : shescape(s))}"
    debug out
    puts out
  end
end

#===============================================================================
# Filter
#===============================================================================

# Empty filter.
class EmptyFilter
  @@instance = nil

  def filter(cursor_arg, candidates)
    return candidates
  end
end

# Runs FZF to help completion.
class FzfFilter
  require 'open3'

  def filter(cursor_arg, candidates)
    if candidates.length <= 1
      return candidates
    end
    debug "Executing fzf with the following candidates..."
    debug_indent do
      query_opt = cursor_arg.to_s.empty? ? "" : "-q #{shescape cursor_arg}"

      sep = "\x1f"

      dedupe_list = []

      Open3.popen2("fzf -d '#{sep}' #{query_opt} --no-multi" \
          + " --read0 --print0 -1 -0 --with-nth 2") do |i,o,t|
        wrote = {}
        index = 0
        candidates.each do |c|
          next if wrote[c.value]

          wrote[c.value] = true
          dedupe_list << c

          just_length = [((c.value.length / 10) + 1) * 10, 30].max
          i.print(index, sep, c.value.ljust(just_length), " ", c.help, "\0")
          index += 1
        end
        i.close()
        debug "Wrote candidates, waiting for selection..."

        ret = []
        result = o.read
        debug "Selection was:"
        result.split("\0").each do |line|
          index = line[/^\d+/].to_i
          c = dedupe_list[index]
          debug {c.inspect}
          ret << c
        end
        return ret
      end
    end
  end
end

#-----------------------------------------------------------
# Engine
#-----------------------------------------------------------
class CompletionEngine
  using CompleterRefinements
  include CompleterHelper

  FINISH_LABEL = :FinishLabel
  FOR_ARG_LABEL = :ForArg

  FOR_AGAIN = 1

  class Sentinel
    def initialize(function)
      @function = function
    end

    attr_reader :function
  end

  RESULT_MAYBE = Sentinel.new("maybe")
  RESULT_NEXT_ARG_MUST =  Sentinel.new("next_arg_must")
  RESULT_FOR_ARG =  Sentinel.new("for_arg")
  RESULT_NEXT_ARG =  Sentinel.new("next_arg")
  RESULT_CONSUME =  Sentinel.new("consume")
  RESULT_UNCONSUME =  Sentinel.new("unconsume")

  STORE_LAST_COMPLETE_TIME = "engine.last_complete_time"
  STORE_LAST_CURSOR_INDEX = "engine.last_cursor_index"
  STORE_LAST_ORIG_ARGS = "engine.last_cursor_args"

  def initialize(shell, orig_args, index, extras)
    @shell = shell

    @orig_args = orig_args

    # All words in the command line.
    @args = orig_args.map { |w| unshescape(w.expand_home) }

    # Cursor arg index; 0-based.
    @cursor_index = index

    # Command name
    @command = @args[0].gsub(%r(^.*/), "")

    @extras = extras

    @index = 0
    @current_consumed = false
    @candidates = []
  end

  attr_reader :shell, :orig_args, :args, :cursor_index, :command,
      :index, :extras

  # Returns the shell and environmental variables.
  def env()
    return @shell.env
  end

  def cursor_arg()
    return args[cursor_index] || ""
  end

  def cursor_orig_arg()
    return orig_args[cursor_index] || ""
  end

  def arg(relative_index = 0)
    i = index + relative_index
    return nil if i < 0 || i > cursor_index
    return args[i] || ""
  end

  def orig_arg(relative_index = 0)
    i = index + relative_index
    return nil if i < 0 || i > cursor_index
    return orig_args[i] || ""
  end

  def at_cursor?()
    return index == cursor_index
  end

  def after_cursor?()
    return index > cursor_index
  end

  def before_cursor?()
    return index < cursor_index
  end

  def current_consumed?
    return @current_consumed
  end

  # Whether a candidate(s) are already registered.
  def has_candidates?()
    return @candidates.size > 0
  end

  # Clear all the candidates that have been added so far.
  def clear_candidates()
    debug "Candidate(s) removed."
    @candidates = []
  end

  # Add a single candidate.
  # If always is true, candidates will be always added, even
  # if the candidate doesn't start with the cursor arg.
  def _candidate_single(cand, always:false)
    debug_indent do
      return unless at_cursor?
      return unless cand
      die "#{cand.inspect} is not a Candidate" unless cand.instance_of? Candidate
      return unless cand.value
      if !always and !cand.has_prefix? cursor_arg
        debug {"candidate rejected."}
        return
      end

      debug {"candidate added: #{cand}"}

      @candidates.push(cand)
    end
  end

  # Push candidates.
  # "args" can be a string, an array of strings, or a proc.
  # If always is true, candidates will be always added, even
  # if they don't start with the cursor arg.
  def candidates(*vals, always:false , &block)
    _detect_invalid_params(vals)
    debug_indent do
      return unless at_cursor?

      vals.each {|val|
        debug {"Possible candidate: val=#{val.inspect}"}
        c = as_candidate(val)
        if c
          _candidate_single c, always:always
        elsif val.respond_to? :each
          val.each {|x| candidates x, always:always}
        elsif val.respond_to? :call
          candidates(val.call(), always:always)
        else
          debug {"Ignoring unsupported candidate: #{val.inspect}"}
        end
      }
      if block
        candidates(block.call(), always:always)
      end
    end
  end

  alias candidate candidates
  alias flag candidates
  alias flags candidates

  def _detect_invalid_params(vals)
    vals.each do |v|
      if v.instance_of? Sentinel
        die "Passing function '#{v.function}' as a method argument is likely a bug."
      end
    end
  end

  def next_arg(force:false)
    block_given? and die "next_arg() doesn't take a block."

    if !force and !current_consumed?
      debug {"[next_arg] -> still at #{index}, not consumed yet"}
    else
      if @index <= @cursor_index
        @index += 1
        @current_consumed = false
      end
      debug {"[next_arg] -> now at #{index}, \"#{arg}\""}

      finish if after_cursor?
    end
    return RESULT_NEXT_ARG
  end

  def unconsume()
    if @current_consumed
      @current_consumed = false
      debug {"arg at #{index} unconsumed."}
    end
    return RESULT_UNCONSUME
  end

  def consume()
    if !@current_consumed
      @current_consumed = true
      debug {"arg at #{index} consumed."}
    end
    return RESULT_CONSUME
  end

  def match?(condition, value)
    debug {"match?: \"#{condition}\", #{shescape value}"}

    if condition.instance_of? String
      return condition == value # For a full match, we're always case sensitive.

    elsif condition.instance_of? Candidate
      return condition.value == value

    elsif condition.instance_of? Regexp
      return value =~ condition

    elsif condition.respond_to? :each
      debug_indent do
        return condition.any?{|x| match?(x, value)}
      end

    else
      die "Unsupported match type: condition"
    end
  end

  def for_arg(match=nil, &block)
    block or die "for_each_word() requires a block."

    last_start_index = -1
    begin
      res = catch FOR_ARG_LABEL do
        while !after_cursor?
          force_next = last_start_index == @index and !current_consumed?
          last_start_index = @index

          debug {"[for_arg](#{index}/#{cursor_index})"}

          next_arg force:force_next

          start_index = @index

          if match == nil or at_cursor? or match? match, arg
            debug {"Executing loop body."}
            debug_indent do
              block.call()
            end
          else
            throw FOR_ARG_LABEL
          end

          # If at_cursor, we need to run the rest of the code after the loop,
          # with the current arg (without advancing the index).
          if start_index == @cursor_index
            throw FOR_ARG_LABEL
          end
        end
      end
    end while res == FOR_AGAIN

    return RESULT_FOR_ARG
  end

  # Exits the inner most for_arg loop.
  def for_break()
    debug "for_break()"
    throw FOR_ARG_LABEL
  end

  # Jump back to the top the inner most for_arg loop and process the
  # next argument.
  def for_next()
    debug "for_next()"
    throw FOR_ARG_LABEL, FOR_AGAIN
  end

  def maybe(*vals, &block)
    _maybe_inner vals, &block
    return RESULT_MAYBE
  end

  def _maybe_inner(vals, &block)
    vals.length == 0 and die "maybe() requires at least one argument."
    _detect_invalid_params(vals)

    return if current_consumed?
    debug {"[maybe](#{index}/#{cursor_index}): #{vals}#{block ? " (has block)" : ""}"}

    debug_indent do
      # If we're at cursor, just add the candidates.
      if at_cursor?
        debug {" at_cursor: adding candidate(s)."}
        candidates vals[0]
        return
      end

      if !match? vals[0], arg
        return
      end

      # Otherwise, eat words.
      debug {"maybe: found a match."}
      consume

      debug_indent do
        1.upto(vals.length - 1) do |i|
          debug {"maybe(): processing arg ##{i} #{vals[i].inspect}"}
          next_arg
          consume
          if at_cursor?
            candidates vals[i]
            finish
          end
        end
      end

      if block
        next_arg
        debug_indent do
          block.call
        end
      end
    end
  end

  def otherwise(&block)
    block or die "otherwise() requires a block."

    return maybe(//) do
      block.call
    end
  end

  def next_arg_must(*vals, &block)
    vals.length == 0 and die "next_arg_must() requires at least one argument."
    _detect_invalid_params(vals)

    debug {"[next_arg_must](#{index}/#{cursor_index}): #{vals}#{block ? " (has block)" : ""}"}

    debug_indent do
      next_arg
      consume

      (vals.length).times do |n|
        if at_cursor?
          candidates vals[n]
          finish
        end
        consume
        next_arg
      end
    end
    return RESULT_NEXT_ARG_MUST
  end

  def finish()
    block_given? and die "finish() doesn't take a block."
    debug "finish()"
    throw FINISH_LABEL
  end

  # If the cursor arg starts with "$", then see if it's expandable.
  def _maybe_handle_variable()
    arg = cursor_orig_arg

    debug { "_maybe_handle_variable(): arg=#{arg}" }

    # First, see if the current arg may be a prefix of an environmental
    # variable, in which case we can complete.
    var_name = shell.variable_completable?(arg)
    if var_name
      debug { "Maybe variable: #{var_name}" }
      env.keys.each do |k|
        if k.has_prefix?(var_name)
          candidate(RAW_MARKER + "$" + k + INCOMPLETE_MARKER) # Raw candidate
        end
      end
      return
    end

    # Next, see if the current arg contains an "expandable" environmental
    # variable. e.g. on bash, $HOME/[TAB] will expand to /home/USER/.
    var_name = shell.variable_expandable?(arg)
    if var_name
      debug "Maybe variable: #{var_name}"
      value = env[var_name]
      if value and File.directory?(value)
        value += "/"
        value += INCOMPLETE_MARKER if is_non_empty_dir(value)
        candidate value, always:true
      end
    end
  end

  def _collect_candidate(&block)
    # Need this so candidates() will accept candidates.
    @index = @cursor_index

    # If the cursor arg starts with a variable name, we want to
    # complete or expand it.
    _maybe_handle_variable

    # Bash unfortunately calls a completion function even after < and >.
    # Give the shell a chance to detect it and do a filename completion.
    shell.maybe_override_candidates self

    # If no one generated candidates yet, let the user-defined code
    # generates some.
    if !has_candidates?
      catch FINISH_LABEL do
        debug "Starting the user block."

        # Start from the first argument, unconsumed.
        @index = 1
        unconsume

        instance_eval(&block)
      end
    end
  end

  # Entry point.
  def run_completion(&block)
    shell.start_completion
    begin
      use_fzf = ALWAYS_FZF

      # Check the cached candidates.
      last_time = Store.instance.get STORE_LAST_COMPLETE_TIME, 0
      cache_age = Time.now.to_f - last_time.to_f

      if (cache_age > 0 and cache_age < CACHE_TIMEOUT) and
          (Store.instance.get(STORE_LAST_CURSOR_INDEX) == cursor_index) and
          (Store.instance.get(STORE_LAST_ORIG_ARGS) == orig_args)
        @candidates = CandidateCache.instance.load()

        debug "Loaded #{@candidates.length} candidate(s) from cache; age=#{cache_age}"

        use_fzf = true if cache_age < AUTO_FZF_TIMEOUT
      end

      if @candidates.length == 0
        # Note, start_completion needs to happen before this, because
        # that's where we read variables from bash.
        _collect_candidate(&block)

        Store.instance.set STORE_LAST_CURSOR_INDEX, cursor_index
        Store.instance.set STORE_LAST_ORIG_ARGS, orig_args

        debug "Saving candidates..."
        CandidateCache.instance.save(@candidates)
        debug "Done saving candidates."
      end

      use_fzf = false unless shell.fzf_supported

      filter = use_fzf ? FzfFilter.new : EmptyFilter.new

      debug "Start adding candidates."

      # Add collected candidates.
      filter.filter(cursor_arg, @candidates).each do |c|
        shell.add_candidate c
      end

      debug "Candidates all added."

      Store.instance.set STORE_LAST_COMPLETE_TIME, Time.now.to_f
    ensure
      shell.end_completion
    end

    Store.instance.save()
    debug "Done"
  end
end


#-----------------------------------------------------------
# Core class
#-----------------------------------------------------------
class Completer

  private

  def __initialize__
  end

  # Install completion
  def do_install(commands, script, extras:nil)
    commands or die "Missing commands."

    # Remove directories from command names.
    commands = commands.map {|p| p.sub(%r(^.*/), "")}
    get_shell.install(commands, script, extras)
  end

  # Perform completion
  def do_completion(cursor_pos, args, extras:nil, &b)
    b or die "do_completion() requires a block."
    shell = get_shell
    engine = CompletionEngine.new shell, args, cursor_pos, extras

    debug <<~EOF
        OrigArgs: #{engine.orig_args.join ", "}
        Args: #{engine.args.join ", "}
        Index: #{engine.cursor_index}
        Current: #{engine.cursor_arg}
        EOF

    engine.run_completion(&b)
  end

  # Main
  public
  def real_main(&b)
    extras = nil

    OptionParser.new { |opts|
      opts.banner = "Usage: [OPTIONS] command-name"

      # Note "-c" must be the last option; otherwise other flags such as
      # "-e" will be ignored.
      opts.on("-c", "Perform completion (shouldn't be used directly)") do
        cursor_pos = ARGV.shift.to_i
        args = ARGV
        do_completion cursor_pos, args, extras:extras, &b
        return
      end

      opts.on("-eEXTRAS", "Extra options to pass to the completion script") do |v|
        extras = v
      end
    }.parse!

    ARGV or die("Missing command name(s).")

    do_install ARGV, $0, extras:extras
  end

  # The entry point called by the outer script.
  public
  def self.define(&b)
    b or die "define() requires a block."

    Completer.new.real_main(&b)
  end
end
