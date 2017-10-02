//bin/true; exec ruby -x "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" git
#!ruby

=begin

# Install

. ~/cbin/misc/completer-cargo.rb

=end

require_relative "completer"
using CompleterRefinements

Completer.define do
  def main()

    maybe "help", build_candidates(%(
        clone      :Clone a repository into a new directory
        init       :Create an empty Git repository or reinitialize an existing one
        add        :Add file contents to the index
        mv         :Move or rename a file, a directory, or a symlink
        reset      :Reset current HEAD to the specified state
        rm         :Remove files from the working tree and from the index
        bisect     :Use binary search to find the commit that introduced a bug
        grep       :Print lines matching a pattern
        log        :Show commit logs
        show       :Show various types of objects
        status     :Show the working tree status
        branch     :List, create, or delete branches
        checkout   :Switch branches or restore working tree files
        commit     :Record changes to the repository
        diff       :Show changes between commits, commit and working tree, etc
        merge      :Join two or more development histories together
        rebase     :Reapply commits on top of another base tip
        tag        :Create, list, delete or verify a tag object signed with GPG
        fetch      :Download objects and refs from another repository
        pull       :Fetch from and integrate with another repository or a local branch
        push       :Update remote refs along with associated objects
        )) do
      finish
    end

    def maybe_finish(arg)
      maybe(arg) {finish}
    end

    maybe_finish build_candidates(%(
       --version
           < Prints the Git suite version that the git program came from.

       --help
           < Prints the synopsis and a list of the most commonly used commands.

       --html-path
           < Print the path, without trailing slash, where Git’s HTML documentation is installed and exit.

       --man-path
           < Print the manpath (see man(1)) for the man pages for this version of Git and exit.

       --info-path
           < Print the path where the Info files documenting this version of Git are installed and exit.
        ))

    # Options to the "git" command self, from "man git".
    for_arg(/^-/) do
      option build_candidates(%(
       -p, --paginate
           < Pipe all output into less (or if set, $PAGER) if standard output is a terminal.

       --no-pager
           < Do not pipe Git output into a pager.

       --bare
           < Treat the repository as a bare repository.

       --no-replace-objects
           < Do not use replacement refs to replace Git objects.

       --literal-pathspecs
           < Treat pathspecs literally (i.e. no globbing, no pathspec magic).

       --glob-pathspecs
           < Add "glob" magic to all pathspec.

       --noglob-pathspecs
           < Add "literal" magic to all pathspec.

       --icase-pathspecs
           < Add "icase" magic to all pathspec.
          ))

      option build_candidates(%(
       -C <path>
           < Run as if git was started in <path> instead of the current working directory.

       --exec-path[=<path>]
           < Path to wherever your core Git programs are installed.

       --git-dir=<path>
           < Set the path to the repository.

       --work-tree=<path>
           < Set the path to the working tree.

       --namespace=<path>
           < Set the Git namespace.
          )), take_dir

      option build_candidates(%(
       -c <name>=<value>
           < Pass a configuration parameter to the command.
          )), [] # no completion
    end

    maybe build_candidates("init       :Create an empty Git repository or reinitialize an existing one") do
      for_arg(/^-/) do
        option build_candidates(%(
       --chroot-sessions
              < Enable chroot session support.

       --no-dbus
              < Do not connect to a D-Bus bus.

       --no-inherit-env
              < Stop jobs from inheriting the initial environment.

       --no-log
              < Disable logging of job output.

       --no-sessions
              < Disable chroot sessions (default).

       --no-startup-event
              < Suppress emission of the initial startup event.

       --session
              < Connect to the D-Bus session bus. This should only be used for testing.

       --user
              < Starts in user mode, as used for user sessions.

       -q, --quiet
              < Reduces output messages to errors only.

       -v, --verbose
              < Outputs verbose messages about job state changes and event emissions to the system console or log, useful for debugging boot.

       --version
              < Outputs version information and exits.
          ))

        option build_candidates(%(
       --confdir directory
              < Read job configuration files from a directory other than the default (/etc/init for process ID 1).

       --logdir directory
              < Write job output log files to a directory other than /var/log/upstart (system mode) or $XDG_CACHE_HOME/upstart (user session mode).
          )), take_dir

        option build_candidates(%(
       --default-console value
              < Default  value for jobs that do not specify a 'console' stanza.

       --startup-event event
              < Specify a different initial startup event from the standard startup(7).
          )), []
      end

    end

  end

  main()
end

=begin
$ cargo
Rust's package manager

Usage:
    cargo <command> [<args>...]
    cargo [options]

Options:
    -h, --help          Display this message
    -V, --version       Print version info and exit
    --list              List installed commands
    --explain CODE      Run `rustc --explain CODE`
    -v, --verbose ...   Use verbose output (-vv very verbose/build.rs output)
    -q, --quiet         No output printed to stdout
    --color WHEN        Coloring: auto, always, never
    --frozen            Require Cargo.lock and cache are up to date
    --locked            Require Cargo.lock is up to date

Some common cargo commands are (see all commands with --list):
    build       Compile the current project
    check       Analyze the current project and report errors, but don't build object files
    clean       Remove the target directory
    doc         Build this project's and its dependencies' documentation
    new         Create a new cargo project
    init        Create a new cargo project in an existing directory
    run         Build and execute src/main.rs
    test        Run the tests
    bench       Run the benchmarks
    update      Update dependencies listed in Cargo.lock
    search      Search registry for crates
    publish     Package and upload this project to the registry
    install     Install a Rust binary

See 'cargo help <command>' for more information on a specific command.
=end

