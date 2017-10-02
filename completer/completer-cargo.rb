. <( exec ruby -x "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" cargo )
: <<'__END_RUBY_CODE__'
#!ruby
def __END_RUBY_CODE__; end

=begin

# Install

. ~/cbin/misc/completer-cargo.rb

=end

require_relative "completer"
using CompleterRefinements

STANDARD_FLAGS = build_candidates(%(
    -h, --help          : Display this message
    -V, --version       : Print version info and exit
    -v, --verbose       : Use verbose output
    -vv                 : Use very verbose output
    -q, --quiet         : No output printed to stdout
    --frozen            : Require Cargo.lock and cache are up to date
    --locked            : Require Cargo.lock is up to date
  ))

Completer.define do

  def take_target()
    lazy_list {%w(i686-unknown-linux-gnu) + read_file_lines("~/.cargo-targets")}
  end

  def option_color
    option "--color \t Use colors", %w(auto always never)
  end

  def option_target
    option "--target \t Target triple", take_target
  end

  def option_manifest_path
    option "--manifest-path \t Path to the manifest to the package to clean", take_file("*.toml")
  end

  def main()
    maybe("--list \t List installed commands") { finish }
    maybe("--explain \t Run `rustc --explain CODE`") { finish }

    for_arg(/^-/) do
      option STANDARD_FLAGS
      option_color
    end

    maybe "help \t Show help for a subcommand" do
      must %w(build check clean doc new init run test bench update search publish install)
      finish
    end

    maybe "clean \t Remove the target directory" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_color
        option_target
        option_manifest_path
      end
      finish
    end

    maybe "build \t Compile the current project" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_color
        option_target
        option_manifest_path
        option build_candidates(%(
            --all                       : Build all packages in the workspace
            --lib                       : Build only this package's library
            --bins                      : Build all binaries
            --examples                  : Build all examples
            --tests                     : Build all tests
            --benches                   : Build all benches
            --release                   : Build artifacts in release mode, with optimizations
            --all-features              : Build all available features
            --no-default-features       : Do not build the `default` feature
            ))
        option build_candidates(%(
            -j N, --jobs N              : Number of parallel jobs, defaults to # of CPUs
            )), take_number
        option build_candidates(%(
            --message-format FMT        : Error format: human, json [default: human]
            )), %w(human json)
        option build_candidates(%(
            -p SPEC, --package SPEC ... : Package to build
            --exclude SPEC ...          : Exclude packages from the build
            --bin NAME                  : Build only the specified binary
            --example NAME              : Build only the specified example
            --test NAME                 : Build only the specified test target
            --bench NAME                : Build only the specified bench target
            --features FEATURES         : Space-separated list of features to also build
            )), [] # Not completable
      end
      finish
    end

    maybe "check \t Analyze the current project and report errors, but don't build object files" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "doc       \t Build this project's and its dependencies' documentation" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "new       \t Create a new cargo project" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "init      \t Create a new cargo project in an existing directory" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "run       \t Build and execute src/main.rs" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "test      \t Run the tests" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "bench     \t Run the benchmarks" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "update    \t Update dependencies listed in Cargo.lock" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "search    \t Search registry for crates" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "publish   \t Package and upload this project to the registry" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
      end
      finish
    end

    maybe "install   \t Install a Rust binary" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
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
