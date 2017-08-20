require 'getoptlong'

class OptionSpecError < StandardError
end

module GetoptInner

  def self.show_bashcomp(all_flags, take_files)
    command = ["bashcomp"]
    command.push "-F" if take_files
    command.push "-c", $0.sub(/^.*\//, "")
    command.push "-f", all_flags.join(" ")
    exec *command
  end

  def self.show_help(help_spec, take_files, usage, usage_proc)
    command = $0.sub(/^.*\//, "")
    if usage_proc
      usage_proc.call()
    else
      puts
      puts "  #{command}: #{usage}"
    end
    puts
    puts("  Usage: #{command} [options]" + if take_files then
        " FILES..." else "" end)
    puts
    help_spec.each {|flags, type, desc|
      puts "  " + flags.join(" ") + type
      puts "\t" + desc
    }
  end

end # module

def getopt(*in_spec, take_files: false, usage: nil, usage_proc: nil, exit_func: nil)
  getopt_spec = []
  flag_to_proc = {}
  flag_getopt_type = {}
  all_flags = []
  help_spec = []

  exit_func = lambda { |code| exit code } unless exit_func

  help_detected = false
  bash_completion_detected = false

  in_spec.push(["h|help", lambda { help_detected = true }, "Show help."])
  in_spec.push(["bash-completion", lambda { bash_completion_detected = true },
      "Print bash completion script."])

  # Decode incoming spec.
  in_spec.each {|in_flag_spec, in_proc, in_desc|
    in_flag_spec =~ /^( [a-z0-9\-\|]* ) ( .* )?/ix
    in_flags, in_type = $1, $2

    # puts "flag=#{in_flags} in_type=#{in_type}" if $DEBUG

    in_type = "=s" if in_type == ":"

    if in_type != "" and (in_type != "=s")
      raise OptionSpecError, "Invalid flag type: #{in_type}"
    end
    if in_flags == ""
      raise OptionSpecError, "Empty flag"
    end

    if !in_proc
      raise OptionSpecError, "Empty callback for #{in_flags}"
    end
    if !in_desc
      raise OptionSpecError, "Empty description for #{in_flags}"
    end

    getopt_type = (if in_type == "=s"
          then GetoptLong::REQUIRED_ARGUMENT
          else GetoptLong::NO_ARGUMENT end)

    flag_list = []

    in_flags.split(/\|/).each { |flag|
      if flag.length == 0
        raise OptionSpecError, "Empty flag for #{in_flags}"
      end
      if flag.length == 1
        flag = "-" + flag
      else
        flag = "--" + flag
      end

      all_flags.push(flag)
      flag_to_proc[flag] = in_proc
      flag_getopt_type[flag] = getopt_type

      flag_list.push(flag)
    }
    help_spec.push([flag_list, in_type, in_desc])
    getopt_spec.push([flag_list, getopt_type].flatten)
  }

  # Parse the arguments.
  opts = GetoptLong.new(*getopt_spec)

  begin
    opts.each {|opt, arg|
      # puts "#{opt.inspect} = #{arg.inspect}" if $DEBUG
      case flag_getopt_type[opt]
      when GetoptLong::NO_ARGUMENT
        flag_to_proc[opt].call
      when GetoptLong::REQUIRED_ARGUMENT
        flag_to_proc[opt].call(arg)
      end
    }
  rescue GetoptLong::Error => e
    exit_func.call 1
    return false
  end

  if help_detected
    GetoptInner::show_help help_spec, take_files, usage, usage_proc
    exit_func.call 0
    return false
  end

  if bash_completion_detected
    GetoptInner::show_bashcomp all_flags, take_files
    exit_func.call 0
    return false
  end
  return true
end

# TODO Tests
