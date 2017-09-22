exec ruby -x "$0" -i -d cargo # for bash
#!ruby

require_relative "completer"

SUBCOMMANDS = %w(build check clean doc new init run test bench update search publish install)

STANDARD_FLAGS = %w(-h --help -V --version -v --verbose -vv -q --quiet --frozen --locked)

TARGETS = read_file_lines("#{ENV['HOME']}/.cargo-targets").push(* %w(i686-unknown-linux-gnu))

Completer.define do
  def take_colors()
    option "--colors", %w(auto always never)
  end

  def take_target()
    option "--target", TARGETS
  end

  def take_package()
    # TODO Package name completion
    option "-p", []
    option "--package", []
  end

  def take_manifest_path()
    option "--manifest_path", [] # TODO Filename completion
  end

  # "flags" is just an alias to "candidates".
  flags STANDARD_FLAGS
  candidates "help"
  candidates SUBCOMMANDS

  # take_files

  # # After "--", only files are allowed.
  # auto_state "--" do
  #   take_files
  # end

  auto_state "help" do
    finish if word(-2) == "help"

    candidates SUBCOMMANDS
  end

  auto_state "new" do
    flags STANDARD_FLAGS
    take_colors

    flags %w(--bin --lib)
    option "--name", []
  end

  auto_state "clean" do
    flags STANDARD_FLAGS
    take_colors

    take_package
    take_manifest_path

    flags %w(--release)
  end

  auto_state "build" do
    flags %w(-h --help --all --lib --bins --tests --benches --release --all-features --no-default-features -v --verbose -q --quiet --frozen --locked)

    take_target
    take_colors

# -p SPEC
# --package SPEC ...
# --exclude SPEC ...
# -j N
# --jobs N
# --bin NAME
# --example NAME
# --examples
# --test NAME
# --bench NAME
# --features FEATURES
# --target TRIPLE
# --manifest-path PATH
# --color WHEN
# --message-format FMT

  end
end
