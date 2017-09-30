. <( exec ruby -wx "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" cargo )
: <<'__END_RUBY_CODE__'
#!ruby
def __END_RUBY_CODE__; end

=begin

# Install

. ~/cbin/misc/completer-cargo.rb

=end

require_relative "completer"
using CompleterRefinements

STANDARD_FLAGS = %w(-h --help -V --version -v --verbose -vv -q --quiet --frozen --locked)

Completer.define do

  def take_target()
    lazy_list {%w(i686-unknown-linux-gnu) + read_file_lines("~/.cargo-targets")}
  end

  def maybe_take_color
    maybe "--color", %w(auto always never)
  end

  def maybe_take_target
    maybe "--target", take_target
  end

  def maybe_take_manifest_path
    maybe "--manifest-path", take_file # Directory??
  end

  def main()
    for_arg(/^-/) do
      maybe STANDARD_FLAGS
      maybe "--list"
      maybe "--explain", [] do
        finish
      end
      maybe_take_color
    end

    maybe "help" do
      next_arg_must %w(build check clean doc new init run test bench update search publish install)
      finish
    end

    maybe "clean" do
      for_arg(/^-/) do
        maybe STANDARD_FLAGS
        maybe_take_color
        maybe_take_target
        maybe_take_manifest_path
      end
      finish
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


__END_RUBY_CODE__
