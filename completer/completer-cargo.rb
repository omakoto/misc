//bin/true; exec ruby -wx "${BASH_VERSION+${BASH_SOURCE[0]}}${ZSH_VERSION+${${(%):-%N}}}" "$@" cargo
#!ruby

=begin

# Install

. ~/cbin/misc/completer-cargo.rb

=end

require_relative "completer"

Completer.define do

  def take_target()
    lazy_list {%w(i686-unknown-linux-gnu) + read_file_lines("~/.cargo-targets")}
  end

  # Parse the "cargo help" style help and build a list of "option"s.
  def build_options(list, &block)
    list.gsub!(/[^\S\n]* \n [^\S\n]* \: \s*/sx, " ") # Line concatenation.

    list.split(/\n/).each do |src_line|
      # Remove leading spaces and comment lines.
      line = src_line.sub(/\s* #.*$/x, "").sub(/^\s+/, "")
      flags, help = line.split(/\s* \: \s*/x, 2)
      next unless flags

      flag_list= []
      comp_list = nil
      flags.split(/[\s\,]+/x).each do |flag|
        case
        when flag =~ /^-/
          flag_list << flag
        when flag =~ /^\.{3,}$/
          # "..." -- ignore.
        when flag == "WHEN"
          comp_list = %w(auto always never)
        when flag == "N"
          comp_list = take_number
        when flag == "TRIPLE"
          comp_list = take_target
        when flag == "PATH"
          if flag_list.include? "--manifest-path"
            comp_list = take_file "*.toml"
          else
            comp_list = take_file
          end
        when flag == "DIR"
          comp_list = take_dir
        when flag == "LIMIT"
          comp_list = take_number
        when flag == "FMT"
          comp_list = %w(human json)
        when flag == "VCS"
          comp_list = %w(git hg pijul fossil none)

        when flag == "CODE"
          comp_list = []

        when flag == "SPEC"     # TODO
          comp_list = []
        when flag == "NAME"     # TODO
          comp_list = []
        when flag == "FEATURES" # TODO
          comp_list = []
        when flag == "VERS" # TODO
          comp_list = []
        when flag == "TAG" # TODO
          comp_list = []
        when flag == "BRANCH" # TODO
          comp_list = []
        when flag == "SHA" # TODO
          comp_list = []
        when flag == "URL" # TODO
          comp_list = []
        when flag == "INDEX" # TODO
          comp_list = []
        when flag == "HOST" # TODO
          comp_list = []
        when flag == "TOKEN" # TODO
          comp_list = []
        else
          die "Can't recognize #{flag}"
        end
      end
      die "flag_list empty." if flag_list.length == 0
      flag_list.each do |f|
        c = f.as_candidate(help:help)
        args = [c]
        args << comp_list if comp_list
        option(*args, &block)
      end
    end
  end

  def main()
    # "Solo" options.
    switch do
      build_options(<<~EOF) {finish}
    -h, --help          :Display this message
    -V, --version       :Print version info and exit
    --list              :List installed commands
    --explain CODE      :Run `rustc --explain CODE`
          EOF
    end

    # Base options.
    for_arg(/^-/) do
      build_options(<<~EOF)
    -v, --verbose ...   :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet         :No output printed to stdout
    --color WHEN        :Coloring: auto, always, never
    --frozen            :Require Cargo.lock and cache are up to date
    --locked            :Require Cargo.lock is up to date
          EOF
    end

    # Subcommands start.
    maybe "help \t Show help for a subcommand" do
      must %w(build check clean doc new init run test bench update search publish install)
      finish
    end

    maybe "clean \t Remove the target directory" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help                   :Print this message
    -p SPEC, --package SPEC ...  :Package to clean artifacts for
    --manifest-path PATH         :Path to the manifest to the package to clean
    --target TRIPLE              :Target triple to clean output for (default all)
    --release                    :Whether or not to clean release artifacts
    -v, --verbose ...            :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet                  :No output printed to stdout
    --color WHEN                 :Coloring: auto, always, never
    --frozen                     :Require Cargo.lock and cache are up to date
    --locked                     :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "build \t Compile the current project" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help                   :Print this message
    -p SPEC, --package SPEC ...  :Package to build
    --all                        :Build all packages in the workspace
    --exclude SPEC ...           :Exclude packages from the build
    -j N, --jobs N               :Number of parallel jobs, defaults to # of CPUs
    --lib                        :Build only this package's library
    --bin NAME                   :Build only the specified binary
    --bins                       :Build all binaries
    --example NAME               :Build only the specified example
    --examples                   :Build all examples
    --test NAME                  :Build only the specified test target
    --tests                      :Build all tests
    --bench NAME                 :Build only the specified bench target
    --benches                    :Build all benches
    --release                    :Build artifacts in release mode, with optimizations
    --features FEATURES          :Space-separated list of features to also build
    --all-features               :Build all available features
    --no-default-features        :Do not build the `default` feature
    --target TRIPLE              :Build for the target triple
    --manifest-path PATH         :Path to the manifest to compile
    -v, --verbose ...            :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet                  :No output printed to stdout
    --color WHEN                 :Coloring: auto, always, never
    --message-format FMT         :Error format: human, json [default: human]
    --frozen                     :Require Cargo.lock and cache are up to date
    --locked                     :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "check \t Analyze the current project and report errors, but don't build object files" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help                   :Print this message
    -p SPEC, --package SPEC ...  :Package(s) to check
    --all                        :Check all packages in the workspace
    --exclude SPEC ...           :Exclude packages from the check
    -j N, --jobs N               :Number of parallel jobs, defaults to # of CPUs
    --lib                        :Check only this package's library
    --bin NAME                   :Check only the specified binary
    --bins                       :Check all binaries
    --example NAME               :Check only the specified example
    --examples                   :Check all examples
    --test NAME                  :Check only the specified test target
    --tests                      :Check all tests
    --bench NAME                 :Check only the specified bench target
    --benches                    :Check all benches
    --release                    :Check artifacts in release mode, with optimizations
    --features FEATURES          :Space-separated list of features to also check
    --all-features               :Check all available features
    --no-default-features        :Do not check the `default` feature
    --target TRIPLE              :Check for the target triple
    --manifest-path PATH         :Path to the manifest to compile
    -v, --verbose ...            :Use verbose output
    -q, --quiet                  :No output printed to stdout
    --color WHEN                 :Coloring: auto, always, never
    --message-format FMT         :Error format: human, json [default: human]
    --frozen                     :Require Cargo.lock and cache are up to date
    --locked                     :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "doc   \t Build this project's and its dependencies' documentation" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help                   :Print this message
    --open                       :Opens the docs in a browser after the operation
    -p SPEC, --package SPEC ...  :Package to document
    --all                        :Document all packages in the workspace
    --no-deps                    :Don't build documentation for dependencies
    -j N, --jobs N               :Number of parallel jobs, defaults to # of CPUs
    --lib                        :Document only this package's library
    --bin NAME                   :Document only the specified binary
    --bins                       :Document all binaries
    --release                    :Build artifacts in release mode, with optimizations
    --features FEATURES          :Space-separated list of features to also build
    --all-features               :Build all available features
    --no-default-features        :Do not build the `default` feature
    --target TRIPLE              :Build for the target triple
    --manifest-path PATH         :Path to the manifest to document
    -v, --verbose ...            :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet                  :No output printed to stdout
    --color WHEN                 :Coloring: auto, always, never
    --message-format FMT         :Error format: human, json [default: human]
    --frozen                     :Require Cargo.lock and cache are up to date
    --locked                     :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "test      \t Run the tests" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help                   :Print this message
    --lib                        :Test only this package's library
    --doc                        :Test only this library's documentation
    --bin NAME ...               :Test only the specified binary
    --bins                       :Test all binaries
    --example NAME ...           :Check that the specified examples compile
    --examples                   :Check that all examples compile
    --test NAME ...              :Test only the specified test target
    --tests                      :Test all tests
    --bench NAME ...             :Test only the specified bench target
    --benches                    :Test all benches
    --no-run                     :Compile, but don't run tests
    -p SPEC, --package SPEC ...  :Package to run tests for
    --all                        :Test all packages in the workspace
    --exclude SPEC ...           :Exclude packages from the test
    -j N, --jobs N               :Number of parallel builds, see below for details
    --release                    :Build artifacts in release mode, with optimizations
    --features FEATURES          :Space-separated list of features to also build
    --all-features               :Build all available features
    --no-default-features        :Do not build the `default` feature
    --target TRIPLE              :Build for the target triple
    --manifest-path PATH         :Path to the manifest to build tests for
    -v, --verbose ...            :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet                  :No output printed to stdout
    --color WHEN                 :Coloring: auto, always, never
    --message-format FMT         :Error format: human, json [default: human]
    --no-fail-fast               :Run all tests regardless of failure
    --frozen                     :Require Cargo.lock and cache are up to date
    --locked                     :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

   maybe "bench     \t Run the benchmarks" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help                   :Print this message
    --lib                        :Benchmark only this package's library
    --bin NAME                   :Benchmark only the specified binary
    --bins                       :Benchmark all binaries
    --example NAME               :Benchmark only the specified example
    --examples                   :Benchmark all examples
    --test NAME                  :Benchmark only the specified test target
    --tests                      :Benchmark all tests
    --bench NAME                 :Benchmark only the specified bench target
    --benches                    :Benchmark all benches
    --no-run                     :Compile, but don't run benchmarks
    -p SPEC, --package SPEC ...  :Package to run benchmarks for
    --all                        :Benchmark all packages in the workspace
    --exclude SPEC ...           :Exclude packages from the benchmark
    -j N, --jobs N               :Number of parallel jobs, defaults to # of CPUs
    --features FEATURES          :Space-separated list of features to also build
    --all-features               :Build all available features
    --no-default-features        :Do not build the `default` feature
    --target TRIPLE              :Build for the target triple
    --manifest-path PATH         :Path to the manifest to build benchmarks for
    -v, --verbose ...            :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet                  :No output printed to stdout
    --color WHEN                 :Coloring: auto, always, never
    --message-format FMT         :Error format: human, json [default: human]
    --no-fail-fast               :Run all benchmarks regardless of failure
    --frozen                     :Require Cargo.lock and cache are up to date
    --locked                     :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "new       \t Create a new cargo project" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help          :Print this message
    --vcs VCS           :Initialize a new repository for the given version
                        :control system (git, hg, pijul, or fossil) or do not
                        :initialize any version control at all (none), overriding
                        :a global configuration.
    --bin               :Use a binary (application) template
    --lib               :Use a library template [default]
    --name NAME         :Set the resulting package name, defaults to the value of <path>
    -v, --verbose ...   :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet         :No output printed to stdout
    --color WHEN        :Coloring: auto, always, never
    --frozen            :Require Cargo.lock and cache are up to date
    --locked            :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "init      \t Create a new cargo project in an existing directory" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help          :Print this message
    --vcs VCS           :Initialize a new repository for the given version
                        :control system (git or hg) or do not initialize any version
                        :control at all (none) overriding a global configuration.
    --bin               :Use a binary (application) template
    --lib               :Use a library template [default]
    --name NAME         :Set the resulting package name
    -v, --verbose ...   :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet         :No output printed to stdout
    --color WHEN        :Coloring: auto, always, never
    --frozen            :Require Cargo.lock and cache are up to date
    --locked            :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "update    \t Update dependencies listed in Cargo.lock" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help                   :Print this message
    -p SPEC, --package SPEC ...  :Package to update
    --aggressive                 :Force updating all dependencies of <name> as well
    --precise PRECISE            :Update a single dependency to exactly PRECISE
    --manifest-path PATH         :Path to the crate's manifest
    -v, --verbose ...            :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet                  :No output printed to stdout
    --color WHEN                 :Coloring: auto, always, never
    --frozen                     :Require Cargo.lock and cache are up to date
    --locked                     :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "run       \t Build and execute src/main.rs" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help                   :Print this message
    --bin NAME                   :Name of the bin target to run
    --example NAME               :Name of the example target to run
    -p SPEC, --package SPEC      :Package with the target to run
    -j N, --jobs N               :Number of parallel jobs, defaults to # of CPUs
    --release                    :Build artifacts in release mode, with optimizations
    --features FEATURES          :Space-separated list of features to also build
    --all-features               :Build all available features
    --no-default-features        :Do not build the `default` feature
    --target TRIPLE              :Build for the target triple
    --manifest-path PATH         :Path to the manifest to execute
    -v, --verbose ...            :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet                  :No output printed to stdout
    --color WHEN                 :Coloring: auto, always, never
    --message-format FMT         :Error format: human, json [default: human]
    --frozen                     :Require Cargo.lock and cache are up to date
    --locked                     :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "install   \t Install a Rust binary" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    --vers VERS               :Specify a version to install from crates.io
    --git URL                 :Git URL to install the specified crate from
    --branch BRANCH           :Branch to use when installing from git
    --tag TAG                 :Tag to use when installing from git
    --rev SHA                 :Specific commit to use when installing from git
    --path PATH               :Filesystem path to local crate to install

    -h, --help                :Print this message
    -j N, --jobs N            :Number of parallel jobs, defaults to # of CPUs
    -f, --force               :Force overwriting existing crates or binaries
    --features FEATURES       :Space-separated list of features to activate
    --all-features            :Build all available features
    --no-default-features     :Do not build the `default` feature
    --debug                   :Build in debug mode instead of release mode
    --bin NAME                :Install only the specified binary
    --bins                    :Install all binaries
    --example NAME            :Install only the specified example
    --examples                :Install all examples
    --root DIR                :Directory to install packages into
    -v, --verbose ...         :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet               :Less output printed to stdout
    --color WHEN              :Coloring: auto, always, never
    --frozen                  :Require Cargo.lock and cache are up to date
    --locked                  :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "search    \t Search registry for crates" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help               :Print this message
    --index INDEX            :Registry index to search in
    --host HOST              :DEPRICATED, renamed to '--index'
    -v, --verbose ...        :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet              :No output printed to stdout
    --color WHEN             :Coloring: auto, always, never
    --limit LIMIT            :Limit the number of results (default: 10, max: 100)
    --frozen                 :Require Cargo.lock and cache are up to date
    --locked                 :Require Cargo.lock is up to date
          EOF
      end
      finish
    end

    maybe "publish   \t Package and upload this project to the registry" do
      for_arg(/^-/) do
      build_options(<<~EOF)
    -h, --help               :Print this message
    --index INDEX            :Registry index to upload the package to
    --host HOST              :DEPRECATED, renamed to '--index'
    --token TOKEN            :Token to use when uploading
    --no-verify              :Don't verify package tarball before publish
    --allow-dirty            :Allow publishing with a dirty source directory
    --manifest-path PATH     :Path to the manifest of the package to publish
    -j N, --jobs N           :Number of parallel jobs, defaults to # of CPUs
    --dry-run                :Perform all checks without uploading
    -v, --verbose ...        :Use verbose output (-vv very verbose/build.rs output)
    -vv                 :Very verbose output
    -q, --quiet              :No output printed to stdout
    --color WHEN             :Coloring: auto, always, never
    --frozen                 :Require Cargo.lock and cache are up to date
    --locked                 :Require Cargo.lock is up to date
          EOF
      end
      finish
    end
  end

  main()
end
