require 'rubygems' # For version check on<1.9
abort "#{$0.sub(/^.*\//, "")} requires ruby >= 2.4" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4')

require 'optparse'
require 'fileutils'
require 'pathname'
require 'singleton'
require 'json'

=begin

Completer.rb: A ruby DSL to write shell completion.

TODO:
- Zsh doesn't split words with : by default. What's the common behavior?

References:
https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html#Programmable-Completion
https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion-Builtins.html#Programmable-Completion-Builtins
=end

# Whether to enable debug or not.
DEBUG = (ENV['COMPLETER_DEBUG'] == "1")

# Whether completion is being performed in case-insensitive mode.
IGNORE_CASE = (ENV['COMPLETER_IGNORE_CASE'] == "1")

# If a completion happens for the same command in a row within this many seconds,
# we reuse the last result.
# Set "-1" to disable cache.
CACHE_TIMEOUT = (ENV['COMPLETER_CACHE_TIMEOUT'] || 5).to_f

# If a completion happen twice in a row for the same input within this amount of time,
# we invoke FZF for menu-style completion, with flag descriptions.
# Set "-1" to disable it.
# Note FZF doesn't seem to work well during zsh's completion, so
# it's disabled for zsh.
AUTO_FZF_TIMEOUT = (ENV['COMPLETER_FZF_TIMEOUT'] || 1.5).to_f

# Whether always use FZF or not.
# Note FZF doesn't seem to work well during zsh's completion, so
# it's disabled for zsh.
ALWAYS_FZF = (ENV['COMPLETER_ALWAYS_FZF'] == "1")

# Max number of candidates to show.
# Note this won't apply when they're shown on zsh/FZF.
MAX_CANDIDATES = (ENV['COMPLETER_MAX_CANDIDATES'] || 50).to_f

# Don't execute the workaround "bind". See BashAgent.
SKIP_BASH_BINDS = (ENV['COMPLETER_SKIP_BASH_BINDS'] == 1)

# When set, this will be passed to FZF via the "--bind" parametr.
# e.g. "tab:accept" to select a candidate with TAB.
FZF_EXTRA_BINDS = ENV['COMPLETER_FZF_BINDS']

# Extra options to pass to FZF.
FZF_OPTS = ENV['COMPLETER_FZF_OPTS']

# Data files and debug log goes to this directory.
APP_DIR = Dir.home + "/.completer/"
Dir.exist?(APP_DIR) or FileUtils.mkdir_p(APP_DIR)

# Debug output goes to this file.
DEBUG_FILE = APP_DIR + "/completer-debug.txt"

RAW_MARKER = "\cr"
FORCE_MARKER = "\cf"
HIDDEN_MARKER = "\ch"
CONTINUE_MARKER = "\cc"
HELP_MARKER = "\t"

#===============================================================================
# Global functions
#===============================================================================

def init_debug()
  $debug_indent_level = 0 unless defined? $debug_indent_level
  $debug_out = nil unless defined? $debug_out
end

# Debug print.
def debug(*args, &b)
  return false unless DEBUG

  init_debug()

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
  init_debug()

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

# Abort execution with a message and a stack trace.
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

# Shell-escape.
# Note for now it's the same thing as bourne_shescape.
def shescape(arg)
  get_shell.shescape(arg)
end

# Shell-unescape.
# Note for now it's the same thing as bourne_unshescape.
def unshescape(arg)
  get_shell.unshescape(arg)
end

# Get an "agent" for the current shell.
# Only bash and zsh are supported for now.
def get_shell()
  $cached_shell = nil unless defined? $cached_shell
  return $cached_shell if $cached_shell

  $cached_shell = (-> {
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

    # If a line starts with leading whitespace + "<", then concatenate it with the previous line.
    arg.gsub!(/\s*\n\s*\</, " : ")

    arg.split(/\n/).each do |line|
      # Remove leading spaces and comments.
      l = line.sub(/^\s+/, "").sub(/\s* \# .*/x, "")

      # : will separate flags and helps
      l, help = l.split(/\s* : \s*/x, 2)

      # flags are separated by spaces or commas.
      if l != nil && l.length > 0
        l.gsub!(/\.{3,}/, " ") # Remove "...".

        # If a line starts with a dash, this is a flag (or a flag list).
        # Then we ignore all words that don't start with "-" in this line.
        line_contains_flags = l =~ /^-/

        # The following characters are typical "meta" characters, so ignore.
        l.split(/[\s\,\<\>\[\]\=]+/).each do |word|
          next if word.length == 0
          next if line_contains_flags && word !~ /^-/

          ret << word.as_candidate(help:help)
        end
      end
    end
  end
  return ret
end

#===============================================================================
# Add functions to String
#===============================================================================
class String
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
  def as_candidate(raw:nil, continue: nil, help: nil, hidden: nil, force: nil)
    # If a string contains a TAB, the following section is a
    # help string.
    (candidate, s_help) = self.split(/ *#{HELP_MARKER} */o, 2)

    # If a candidate starts with an ESC, it's a raw candidate.
    candidate.sub!(/^([#{FORCE_MARKER}#{RAW_MARKER}#{HIDDEN_MARKER}#{CONTINUE_MARKER}]*) \s*/xo, "")
    prefix = $1

    s_raw = prefix.index(RAW_MARKER) != nil
    s_hidden = prefix.index(HIDDEN_MARKER) != nil
    s_continue = prefix.index(CONTINUE_MARKER) != nil
    s_force = prefix.index(FORCE_MARKER) != nil

    # If one is provided as an argument, use it.
    raw = s_raw if raw == nil
    continue = s_continue if continue == nil
    help = s_help if help == nil
    hidden = s_hidden if hidden == nil
    force = s_force if force == nil

    return Candidate.new(candidate.strip, raw:raw, continue:continue, help:help&.strip, \
        hidden: hidden, force: force)
  end
end

#===============================================================================
# LazyList wraps a block that generates Enumerator and only executes it when
# someone asks for the values.
#===============================================================================
class LazyList
  include Enumerable

  def initialize(&block)
    block or die "block must be provided."
    @block = block
    @list = nil
  end

  def each(&block)
    @list = @block.call() unless @list
    @list.each(&block) if @list
  end
end

#===============================================================================
# Candidate represents a single candidate.
#===============================================================================
class Candidate
  def initialize(value, raw:false, continue:false, help: "", hidden:false, \
      force:false)
    value or die "Empty candidate detected."

    @value = value.chomp
    @raw= raw
    @continue = continue
    @help = help == "" ? nil : help
    @hidden = hidden
    @force = force
  end

  # The candidate text.
  attr_reader :value

  # Raw candidates will be appended to the command without escaping.
  # Normally, when a candidate containing special characters is added to the
  # command like, the value will be escaped. For example, $HOME will be added
  # to the command line as '$HOME'.
  # If a completion function wants to add $HOME as-is, make it a raw candidate.
  def raw?()
    return @raw
  end

  # When a candidate "continues", it's may be a prefix of another text.
  # A non-continue candidate will be followed by a space when completed.
  def continue?()
    return @continue
  end

  # Help text, bash can't show it, but FZF and zsh can.
  attr_reader :help

  # Hidden candidates are now shown in the candidate list, but still understood
  # by the logic.
  def hidden?()
    return @hidden
  end

  # "Force" candidates are not filtered out even if the cursor word is not
  # a prefix of them.
  def force?()
    return @force
  end

  # Whether a candidate is "hidden" or not. Hidden candidates won't be shown to
  # the user, but they'll still be used to parse arguments.
  def has_prefix?(prefix)
    return @value.has_prefix?(prefix)
  end

  def as_candidate()
    return self
  end

  def to_s()
    return "{Candidate:value=#{shescape value}#{raw? ? " [raw]" : ""}" +
        "#{continue? ? " [continue]" : ""}" +
        "#{force? ? " [force]" : ""}" +
        "#{help ? " " + help : ""}}"
  end

  def to_parsable()
    ret = ""
    ret << RAW_MARKER if raw?
    ret << CONTINUE_MARKER if continue?
    ret << FORCE_MARKER if force?
    ret << value
    if help
      ret << HELP_MARKER
      ret << help
    end
    return ret
  end
end

#===============================================================================
# Helpers used by completion functions.
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
          cand = path.to_s + "/"
          cand = cand.as_candidate(continue:is_non_empty_dir(path))
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

    if dir != "" and !Dir.exist? dir
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
      ret = ret.reject {|x| x =~/^#/ }
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
          next ("-1".."-9").to_a + ("0".."9").to_a
        else
          next ("0".."9")
        end
      else
        next ("0".."9").map {|x| prefix + x }
      end
    end
  end

  def take_file(wildcard="*", prefix:nil)
    lazy_list { get_matched_files (prefix || arg), wildcard }
  end

  def take_dir(prefix:nil)
    lazy_list { get_matched_dirs (prefix || arg) }
  end

  def take_number(prefix:nil, allow_negative:false)
    lazy_list do
      get_matched_numbers((prefix || arg), allow_negative:allow_negative) \
          .map{|v| v.as_candidate(continue:true)}
    end
  end
end

#===============================================================================
# Class to store the information from the previous invocation, which is used to
# check if the cached candidates are still valid.
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

class CandidateCache
  include Singleton

  STORE_FILE = APP_DIR + "last_candidates.dat"

  def initialize
  end

  # Save candidates in the cache.
  def save(candidates)
    open(STORE_FILE, "w") do |out|
      candidates.each do |c|
        out.puts c.to_parsable
      end
    end
  end

  # Return the cached candidates.
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

  def supports_fzf?()
    return false
  end

  def supports_menu_completion?
    return false
  end

  def shescape(arg)
    bourne_shescape arg
  end

  def unshescape(arg)
    bourne_unshescape arg
  end

  def install(commands, script, extras)
    die "install() must be overridden."
  end

  def fix_args(cursor_index, args)
    return [cursor_index, args]
  end

  def add_candidate(candidate)
    die "add_candidate() must be overridden."
  end

  def start_completion(cursor_index, args)
  end

  def end_completion()
  end

  def maybe_override_candidates(engine)
    # Nothing to do by default.
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

# Bash interface.
class BashAgent < BasicShellAgent
  SECTION_SEPARATOR = "\n-*-*-*-COMPLETER-*-*-*-\n"

  def supports_fzf?()
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
        if (( ! #{(SKIP_BASH_BINDS ? "1" : "0")} )) ; then
          bind '"\\ecp1": overwrite-mode'
          bind '"\\ecp2": complete'
          bind '"\\C-i": "\\ecp1\\ecp1\\ecp2"'
        fi

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
          export COMP_WORDBREAKS
          . <( __completer_context_passer |
              ruby -wx "#{script_file}" #{extra_option} -c -- \
                  "$COMP_CWORD" "${COMP_WORDS[@]}" )
        }
        EOF

    commands.each do |c|
      puts "complete -o nospace -F #{func} -- #{c}"
    end
  end

  def fix_args(cursor_index, args)
    # Due to weird handling of COMP_WORDBREAKS on bash, we need some workaround
    # here.

    # First, remove all args after the cursor. We won't need them anyway.
    args = args[0, cursor_index + 1]

# TODO Test this case.
    wordbreaks = ENV['COMP_WORDBREAKS'].to_s
    if wordbreaks != "" && args[cursor_index] =~ /^[#{ Regexp.quote(wordbreaks) }]+$/x
      # If the cursor word only consists of COMP_WORDBREAKS chars, then we
      # pretend we're at the arg after it.
      cursor_index += 1
      args << ""
      debug "Fixed args. Now at #{cursor_index}"
    end

    return [cursor_index, args]
  end

  # Called when completion is about to start.
  def start_completion(cursor_index, args)
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
    s += " " unless candidate.continue?

    # Output will be eval'ed, so need double-escaping unless raw.
    out = candidate.raw? ? s : shescape(s)
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

Note zsh always seems to do variable expansions, so we don't have to do it,
unlike BashAgent.

=end
class ZshAgent < BasicShellAgent
  def initialize()
    @candidates = []
  end

  def supports_menu_completion?
    return true # FZF hangs when invoked during completion.
  end

  def install(commands, script, extras)

    command = commands[0]
    func = "_#{command.gsub(/[^a-z0-9]/i) {|c| "_" + c.ord.to_s(16)}}_completion"

    debug {"Installing zsh completion for '#{command}', function='#{func}'"}

    script_file = File.expand_path $0

    extra_option = (extras == nil or extras == "") ? "" : "-e #{shescape extras}"

    puts <<~EOF
        function #{func} {
          . <(ruby -wx "#{script_file}" #{extra_option} -c -- \
              "$(( $CURRENT - 1 ))" "${words[@]}" )
        }
        EOF

    commands.each do |c|
      puts "compdef #{func} #{c}"
    end
  end

  def add_candidate(candidate)
    s = shescape(candidate.value)
    s += " " unless candidate.continue?

    # -S '' tells zsh not to add a space afterward. (because we do it by ourselves.)
    # -Q prevents zsh from quoting metacharacters in the results, which we do too.
    # -f treats the result as filenames.
    # -X description -> TODO This seems to be a wrong flag to use.
    # -U suppress filtering by zsh

    fileopt = File.exist?(s) ? "-f" : ""

    desc = candidate.value
    if candidate.help
      desc = desc.ljust([40, ((desc.length / 10) + 1) * 10].max)
      desc << ": "
      desc << candidate.help
    end

    # Need -Q to make zsh preserve the last space.
    out = "COMPLETER_D=(#{shescape desc})\n" + \
        "compadd -S '' -Q -U #{fileopt} -d COMPLETER_D -- #{(candidate.raw? ? s : shescape(s))}"
    debug out
    puts out
  end

  # def end_completion()
  #   puts "compadd -S '' -Q -U -F COMPLETER_CANDIDATES_VAL -d COMPLETER_CANDIDATES_DISP"
  # end
end

#===============================================================================
# Filters
#===============================================================================

# Empty filter.
class EmptyFilter
  @@instance = nil

  def filter(cursor_arg, candidates)
    return candidates
  end
end

# Run FZF to help completion.
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

      bind_opt = FZF_EXTRA_BINDS ? "--bind=#{shescape FZF_EXTRA_BINDS}" : ""

      Open3.popen2("fzf -d '#{sep}' #{query_opt} --no-multi" \
          + " #{bind_opt} #{FZF_OPTS}" \
          + " --read0 --print0 -1 -0 --with-nth 2") do |i,o,t|
        wrote = {}
        index = 0
        candidates.each do |c|
          next if wrote[c.value]

          wrote[c.value] = true
          dedupe_list << c

          just_length = [((c.value.length / 10) + 1) * 10, 40].max
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
# Core logic.
#-----------------------------------------------------------
class CompletionCore
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
  RESULT_NEXT_ARG_MUST =  Sentinel.new("must")
  RESULT_FOR_ARG =  Sentinel.new("for_arg")
  RESULT_SWITCH =  Sentinel.new("switch")
  RESULT_NEXT_ARG =  Sentinel.new("next_arg")

  STORE_LAST_COMPLETE_TIME = "engine.last_complete_time"
  STORE_LAST_CACHE_TIME = "engine.last_cache_time"
  STORE_LAST_CURSOR_INDEX = "engine.last_cursor_index"
  STORE_LAST_ORIG_ARGS = "engine.last_cursor_args"
  STORE_LAST_CWD = "engine.last_cwd"

  def initialize(shell, orig_args, index, extras)
    @shell = shell

    # Shell specific preprocess on arguments.
    index, orig_args = shell.fix_args(index, orig_args)

    @orig_args = orig_args

    # All words in the command line.
    @args = orig_args.map { |w| unshescape(w.expand_home) }

    # Cursor arg index; 0-based.
    @cursor_index = index

    # Command name
    @command = @args[0].gsub(%r(^.*/), "")

    @extras = extras

    @index = 0
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

  # Whether a candidate(s) are already registered.
  def has_candidates?()
    return @candidates.size > 0
  end

  # Clear all the candidates that have been added so far.
  def clear_candidates()
    debug "Candidate(s) removed."
    @candidates = []
  end

  # Add a single Candidate.
  def _candidate_single(cand)
    debug_indent do
      return unless at_cursor?
      return unless cand
      die "#{cand.inspect} is not a Candidate" unless cand.instance_of? Candidate
      return if (cand.value == nil) or (cand.value.rstrip().length == 0)
      if !(cand.force? or cand.has_prefix? cursor_arg)
        debug {"candidate rejected."}
        return
      end
      if cand.hidden?
        debug {"candidate hidden."}
        return
      end

      debug {"candidate added: #{cand}"}

      @candidates.push(cand)
    end
  end

  # Directly add candidates.
  # "args" can be a string/Candidate, an array of strings/Candidate, or a proc.
  def candidates(*vals, &block)
    _detect_invalid_params(vals)
    debug_indent do
      return unless at_cursor?

      vals.each do |val|
        debug {"Possible candidate: val=#{val.inspect}"}
        c = nil
        if val.instance_of? Candidate
          c = val
        elsif val.instance_of? String
          c = val.as_candidate()
        end

        if c
          _candidate_single c
        elsif val.respond_to? :each
          val.each {|x| candidates x}
        elsif val.respond_to? :call
          candidates(val.call())
        else
          debug {"Ignoring unsupported candidate: #{val.inspect}"}
        end
      end
      if block
        candidates(block.call())
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

  def next_arg()
    block_given? and die "next_arg() doesn't take a block."

    if @index <= @cursor_index
      @index += 1
    end
    debug {"[next_arg] -> now at #{index}, \"#{arg}\""}

    finish if after_cursor?
    return RESULT_NEXT_ARG
  end

  def match?(condition, value)
    debug {"match?: \"#{condition}\", #{shescape value}"}

    if condition.instance_of? String
      return condition.as_candidate().value == value # For a full match, we're always case sensitive.

    elsif condition.instance_of? Candidate
      return condition.value == value

    elsif condition.instance_of? Regexp
      return value =~ condition

    elsif condition.respond_to? :each
      debug_indent do
        return condition.any?{|x| match?(x, value)}
      end

    else
      die "Unsupported match type: #{condition == nil ? "nil" : condition.inspect}"
    end
  end

  def switch(&block)
    block or die "switch() requires a block."
    for_arg(nil, once:true, method:"switch", &block)
    return RESULT_SWITCH
  end

  def for_arg(match=nil, once:false, method:"for_arg", &block)
    block or die "#{method}() requires a block."

    last_start_index = -1
    begin
      res = catch FOR_ARG_LABEL do
        while !after_cursor?
          # If the index hasn't changed, force advance.
          force_next = (last_start_index == @index)
          last_start_index = @index
          next_arg if force_next

          debug {"[#{method}](#{index}/#{cursor_index})"}

          start_index = @index

          if match == nil or at_cursor? or match? match, arg
            debug {"Executing #{method} body."}
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
          break if once
        end
      end
    end while (res == FOR_AGAIN) && !once

    return RESULT_FOR_ARG
  end

  # Exits the inner most for_arg loop, or switch.
  def break_for(method:"break_for")
    debug "break_for()"
    begin
      throw FOR_ARG_LABEL
    rescue UncaughtThrowError
      die "#{method}() used out of for_arg() or switch()"
    end
  end

  # Jump back to the top the inner most for_arg loop, or switch.
  def next_for(method:"next_for")
    debug "next_for()"
    begin
      throw FOR_ARG_LABEL, FOR_AGAIN
    rescue UncaughtThrowError
      die "#{method}() used out of for_arg() or switch()"
    end
  end

  def option(*vals, &block)
    maybe(*vals, fallthrough:false, method:"option", &block)
  end

  def maybe(*vals, fallthrough:true, method:"maybe", &block)
    vals.length == 0 and die "#{method}() requires at least one argument."
    _detect_invalid_params(vals)

    debug {"[#{method}](#{index}/#{cursor_index}): #{vals}#{block ? " (has block)" : ""}"}

    debug_indent do
      # If we're at cursor, just add the candidates.
      if at_cursor?
        debug {" at_cursor: adding candidate(s)."}
        candidates vals[0]

        # Note in this case, we don't break the for, but fall-through,
        # to execute the rest of the maybe's to collect all candidates.
        return
      end

      if match? vals[0], arg
        # Otherwise, eat words.
        debug {"#{method}: found a match."}
        next_arg

        debug_indent do
          1.upto(vals.length - 1) do |i|
            debug {"#{method}(): processing arg ##{i} #{vals[i].inspect}"}
            if at_cursor?
              candidates vals[i]
              finish
            end
            next_arg
          end
        end

        if block
          debug_indent do
            block.call
          end
        end

        fallthrough or next_for(method:method)
      end # match
    end
    return RESULT_MAYBE
  end

  def otherwise(&block)
    block or die "otherwise() requires a block."

    return maybe(//, method:"otherwise") do
      block.call
    end
  end

  def must(*vals, &block)
    vals.length == 0 and die "must() requires at least one argument."
    _detect_invalid_params(vals)

    debug {"[must](#{index}/#{cursor_index}): #{vals}#{block ? " (has block)" : ""}"}

    debug_indent do
      vals.length.times do |n|
        if at_cursor?
          candidates vals[n]
          finish
        end
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
          candidate(("$" + k).as_candidate(raw:true, continue:true))
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
        candidate value.as_candidate(force:true, continue:is_non_empty_dir(value))
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

        # Start from the first argument.
        @index = 1

        instance_eval(&block)
      end
    end
  end

  # Entry point.
  def run_completion(&block)
    shell.start_completion(cursor_index, args)
    begin
      # Check the cached candidates.
      now = Time.now.to_f
      last_time = Store.instance.get STORE_LAST_COMPLETE_TIME, 0
      cache_time = Store.instance.get STORE_LAST_CACHE_TIME, 0

      last_age = now - last_time.to_f
      cache_age = now - cache_time.to_f

      repeat_call = \
          (Store.instance.get(STORE_LAST_CURSOR_INDEX) == cursor_index) &&
          (Store.instance.get(STORE_LAST_ORIG_ARGS) == orig_args) &&
          (Store.instance.get(STORE_LAST_CWD) == Dir.pwd)

      if (cache_age > 0) && (cache_age < CACHE_TIMEOUT) && repeat_call
        @candidates = CandidateCache.instance.load()

        debug "Loaded #{@candidates.length} candidate(s) from cache; age=#{cache_age}"
      end

      # If no candidates are read from the cache, run the user-defined method.
      if @candidates.length == 0
        # Note, start_completion needs to happen before this, because
        # that's where we read variables from bash.
        _collect_candidate(&block)

        Store.instance.set STORE_LAST_CACHE_TIME, Time.now.to_f
        Store.instance.set STORE_LAST_CURSOR_INDEX, cursor_index
        Store.instance.set STORE_LAST_ORIG_ARGS, orig_args
        Store.instance.set STORE_LAST_CWD, Dir.pwd

        debug "Saving candidates..."
        CandidateCache.instance.save(@candidates)
        debug "Done saving candidates."
      end

      # Candidates collected, print them, maybe optionally passing
      # through FZF.
      use_fzf = shell.supports_fzf? && (ALWAYS_FZF || (last_age < AUTO_FZF_TIMEOUT && repeat_call))

      filter = use_fzf ? FzfFilter.new : EmptyFilter.new

      debug "Start adding candidates."

      # Add collected candidates.
      count = 0
      filter.filter(cursor_arg, @candidates).each do |c|
        count += 1
        if count <= MAX_CANDIDATES or shell.supports_menu_completion?
          shell.add_candidate c
        else
          shell.add_candidate "[REST OMITTED]".as_candidate
          break
        end
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
# Entry point class
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
    engine = CompletionCore.new shell, args, cursor_pos, extras

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

    install = true

    OptionParser.new { |opts|
      opts.on("-c", "Run in completion mode. If not specified, #{$0} prints a install script.") do
        install = false
      end

      opts.on("-eEXTRAS", "Extra options to pass to the completion script") do |v|
        extras = v
      end
    }.order!

    if install
      (ARGV.length == 0) && die("Missing command name(s).")
      do_install ARGV, $0, extras:extras
    else
      # run completion
      cursor_pos = ARGV.shift.to_i
      (ARGV.length == 0) && die("Missing arguments.")
      do_completion cursor_pos, ARGV, extras:extras, &b
    end
  end

  # The entry point called by the outer script.
  public
  def self.define(&b)
    b or die "define() requires a block."

    Completer.new.real_main(&b)
  end
end
