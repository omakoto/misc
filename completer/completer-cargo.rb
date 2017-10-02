//bin/true; exec ruby -x "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" cargo
#!ruby

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

  def option_message_format
    option build_candidates(%(
        --message-format FMT        : Error format: human, json [default: human]
        )), %w(human json)
  end

  def option_jobs
    option build_candidates(%(
        -j N, --jobs N              : Number of parallel jobs, defaults to # of CPUs
        )), take_number
  end

  def option_features
        option build_candidates(%(
            --all-features              : Build all available features
            --no-default-features       : Do not build the `default` feature
            ))
        option build_candidates(%(
            --features FEATURES         : Space-separated list of features to also build
            )), [] # Not completable
  end

  def main()
    # "Solo" options.
    maybe("--list \t List installed commands") { finish }
    maybe("--explain \t Run `rustc --explain CODE`") { finish }

    # Base options.
    for_arg(/^-/) do
      option STANDARD_FLAGS
      option_color
    end

    # Subcommands start.
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

    maybe [
            "build \t Compile the current project",
            "check \t Analyze the current project and report errors, but don't build object files",
            "doc   \t Build this project's and its dependencies' documentation"
          ] do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_color
        option_target
        option_manifest_path
        option_features
        option_jobs
        option_message_format
        option build_candidates(%(
            --all                       : Build all packages in the workspace
            --lib                       : Build only this package's library
            --bins                      : Build all binaries
            --examples                  : Build all examples
            --tests                     : Build all tests
            --benches                   : Build all benches
            --release                   : Build artifacts in release mode, with optimizations
            ))
        option build_candidates(%(
            -p SPEC, --package SPEC ... : Package to build
            --exclude SPEC ...          : Exclude packages from the build
            --bin NAME                  : Build only the specified binary
            --example NAME              : Build only the specified example
            --test NAME                 : Build only the specified test target
            --bench NAME                : Build only the specified bench target
            )), [] # Not completable
      end
      finish
    end

    maybe "test      \t Run the tests" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_color
        option_target
        option_manifest_path
        option_features
        option_jobs
        option_message_format
        option build_candidates(%(
            --all                       : Test all packages in the workspace
            --lib                       : Test only this package's library
            --bins                      : Test all binaries
            --examples                  : Test all examples
            --tests                     : Test all tests
            --benches                   : Test all benches
            --release                   : Test artifacts in release mode, with optimizations
            --doc                       : Test only this library's documentation

            --no-fail-fast              : Run all tests regardless of failure
            ))
        option build_candidates(%(
            -p SPEC, --package SPEC ... : Package to build
            --exclude SPEC ...          : Exclude packages from the build
            --bin NAME                  : Test only the specified binary
            --example NAME              : Test only the specified example
            --test NAME                 : Test only the specified test target
            --bench NAME                : Test only the specified bench target
            )), [] # Not completable
      end
      finish
    end

    maybe "bench     \t Run the benchmarks" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_color
        option_target
        option_manifest_path
        option_features
        option_jobs
        option_message_format
        option build_candidates(%(
            --all                       : Benchmark all packages in the workspace
            --lib                       : Benchmark only this package's library
            --bins                      : Benchmark all binaries
            --examples                  : Benchmark all examples
            --tests                     : Benchmark all tests
            --benches                   : Benchmark all benches
            --no-fail-fast              : Run all tests regardless of failure
            ))
        option build_candidates(%(
            -p SPEC, --package SPEC ... : Package to build
            --exclude SPEC ...          : Exclude packages from the build
            --bin NAME                  : Benchmark only the specified binary
            --example NAME              : Benchmark only the specified example
            --test NAME                 : Benchmark only the specified test target
            --bench NAME                : Benchmark only the specified bench target
            )), [] # Not completable
      end
      finish
    end

    maybe [
            "new       \t Create a new cargo project",
            "init      \t Create a new cargo project in an existing directory"
          ] do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_color
        option build_candidates(%(
            --bin               : Use a binary (application) template
            --lib               : Use a library template [default]
            ))
        option build_candidates(%(
            --vcs VCS           : Initialize a new repository for the given version control system
            )), %w(git hg pijul fossil none)
        option build_candidates(%(
            --name NAME         : Set the resulting package name, defaults to the value of <path>
            )), []
      end
      finish
    end

    maybe "update    \t Update dependencies listed in Cargo.lock" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_manifest_path
        option build_candidates(%(
            --aggressive                : Force updating all dependencies of <name> as well
            ))
        option build_candidates(%(
            -p SPEC, --package SPEC ... : Package to update
            --precise PRECISE           : Update a single dependency to exactly version
            )), [] # Not completable
      end
      finish
    end

    maybe "run       \t Build and execute src/main.rs" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_color
        option_target
        option_manifest_path
        option_features
        option_jobs
        option_message_format
        option build_candidates(%(
            --release                   : Build artifacts in release mode, with optimizations
            ))
        option build_candidates(%(
            -p SPEC, --package SPEC ... : Package to build
            --bin NAME                  : Build only the specified binary
            --example NAME              : Build only the specified example
            )), [] # Not completable
      end
      finish
    end

    maybe "install   \t Install a Rust binary" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_color
        option_target
        option_jobs
        option_features
        option build_candidates(%(
            --debug                   : Build in debug mode instead of release mode
            --bins                    : Install all binaries
            --examples                : Install all examples
            -f, --force               : Force overwriting existing crates or binaries
           ))
        option build_candidates(%(
            --bin NAME                : Install only the specified binary
            --example NAME            : Install only the specified example
            --vers VERS               : Specify a version to install from crates.io
            --git URL                 : Git URL to install the specified crate from
            --branch BRANCH           : Branch to use when installing from git
            --tag TAG                 : Tag to use when installing from git
            --rev SHA                 : Specific commit to use when installing from git
            )), [] # Not completable
        option build_candidates(%(
            --path PATH               : Filesystem path to local crate to install
            --root DIR                : Directory to install packages into
            )), take_dir
      end
      finish
    end

    maybe "search    \t Search registry for crates" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option build_candidates(%(
            --index INDEX            : Registry index to search in
            )), []
        option build_candidates(%(
            --limit LIMIT            : Limit the number of results (default: 10, max: 100)
            )), take_number
      end
      finish
    end

    maybe "publish   \t Package and upload this project to the registry" do
      for_arg(/^-/) do
        option STANDARD_FLAGS
        option_manifest_path
        option build_candidates(%(
          --no-verify              : Don't verify package tarball before publish
          --allow-dirty            : Allow publishing with a dirty source directory
          --dry-run                : Perform all checks without uploading
            ))
        option build_candidates(%(
            --index INDEX            : Registry index to search in
            --token TOKEN            : Token to use when uploading
            )), []
        option build_candidates(%(
            --limit LIMIT            : Limit the number of results (default: 10, max: 100)
            )), take_number
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

