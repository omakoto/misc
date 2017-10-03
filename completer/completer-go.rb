//bin/true; exec ruby -wx "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" go
#!ruby

require_relative "completer"
using CompleterRefinements

Completer.define do
  def take_buildmode
    lazy_list do
      ret = []
      (ENV['MOCK_GO_STDOUT'] || %x(go help buildmode)).scan(/\s\-buildmode\=(\S+)/) do |x|
        ret << x
      end
      ret
    end
  end

  # Parse the "cargo help" style help and build a list of "option"s.
  def build_options(list, &block)
    # Append : to all lines tha begins with "-"
    list.gsub!(/^(\s* \- [^\n]+ ) \n/x, "\\1:\n")
    list.gsub!(/[^\S\n]* \n [^\S\n]* (?= [^-\s])/sx, " ") # Line concatenation.

    list.split(/\n/).each do |src_line|
      # Remove leading spaces and comment lines.
      line = src_line.sub(/\s* #.*$/x, "").sub(/^\s+/, "")
      flag_arg, help = line.split(/\s* : \s*/x, 2)

      next unless flag_arg

      flag, arg = flag_arg.split(/\s+/, 2)

      comp_list = nil
      case
      when arg == nil
        # ok
      when arg == "n"
        comp_list = take_number
      when arg == "dir"
        comp_list = take_dir

      when flag == "-buildmode"
        comp_list = take_buildmode

      when flag == "-compiler"
        comp_list = %w(gccgo gc)

      when arg == "'arg list'",  arg == "'flag list'", arg == "'tag list'", \
          arg == "'cmd args'"
        comp_list = []

      when arg == "suffix"
        comp_list = []
      else
        die "Can't recognize #{flag}"
      end

      c = flag.as_candidate(help:help)
      args = [c]
      args << comp_list if comp_list
      option(*args, &block)
    end
  end

  def main()

    # Subcommands start.
    maybe "help \t Show help for a subcommand" do
      must build_candidates(%(
  build       :compile packages and dependencies
  clean       :remove object files
  doc         :show documentation for package or symbol
  env         :print Go environment information
  bug         :start a bug report
  fix         :run go tool fix on packages
  fmt         :run gofmt on package sources
  generate    :generate Go files by processing source
  get         :download and install packages and dependencies
  install     :compile and install packages and dependencies
  list        :list packages
  run         :compile and run Go program
  test        :test packages
  tool        :run specified go tool
  version     :print Go version
  vet         :run go tool vet on packages
        ))
      finish
    end

    maybe "build       \tcompile packages and dependencies" do
      for_arg(/^-/) do
      build_options(<<~EOF)
  -a
    force rebuilding of packages that are already up-to-date.
  -n
    print the commands but do not run them.
  -p n
    the number of programs, such as build commands or
    test binaries, that can be run in parallel.
    The default is the number of CPUs available.
  -race
    enable data race detection.
    Supported only on linux/amd64, freebsd/amd64, darwin/amd64 and windows/amd64.
  -msan
    enable interoperation with memory sanitizer.
    Supported only on linux/amd64,
    and only with Clang/LLVM as the host C compiler.
  -v
    print the names of packages as they are compiled.
  -work
    print the name of the temporary work directory and
    do not delete it when exiting.
  -x
    print the commands.

  -asmflags 'flag list'
    arguments to pass on each go tool asm invocation.
  -buildmode mode
    build mode to use. See 'go help buildmode' for more.
  -compiler name
    name of compiler to use, as in runtime.Compiler (gccgo or gc).
  -gccgoflags 'arg list'
    arguments to pass on each gccgo compiler/linker invocation.
  -gcflags 'arg list'
    arguments to pass on each go tool compile invocation.
  -installsuffix suffix
    a suffix to use in the name of the package installation directory,
    in order to keep output separate from default builds.
    If using the -race flag, the install suffix is automatically set to race
    or, if set explicitly, has _race appended to it. Likewise for the -msan
    flag. Using a -buildmode option that requires non-default compile flags
    has a similar effect.
  -ldflags 'flag list'
    arguments to pass on each go tool link invocation.
  -linkshared
    link against shared libraries previously created with -buildmode=shared.
  -pkgdir dir
    install and load all packages from dir instead of the usual locations.
    For example, when building with a non-standard configuration,
    use -pkgdir to keep generated packages in a separate location.
  -tags 'tag list'
    a space-separated list of build tags to consider satisfied during the
    build. For more information about build tags, see the description of
    build constraints in the documentation for the go/build package.
  -toolexec 'cmd args'
    a program to use to invoke toolchain programs like vet and asm.
    For example, instead of running asm, the go command will run
    'cmd args /path/to/asm <arguments for asm>'.
          EOF
      end
      finish
    end

    maybe "clean       \tremove object files" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "doc         \tshow documentation for package or symbol" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "env         \tprint Go environment information" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "bug         \tstart a bug report" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "fix         \trun go tool fix on packages" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "fmt         \trun gofmt on package sources" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "generate    \tgenerate Go files by processing source" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "get         \tdownload and install packages and dependencies" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "install     \tcompile and install packages and dependencies" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "list        \tlist packages" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "run         \tcompile and run Go program" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "test        \ttest packages" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "tool        \trun specified go tool" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "version     \tprint Go version" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end

    maybe "vet         \trun go tool vet on packages" do
      for_arg(/^-/) do
      build_options(<<~EOF)
          EOF
      end
      finish
    end
  end

  main()
end
