# ruby script \
. <(bashcomp.rb -d -i cargo <<RUBY_END


# TODO How to define custom option?
# TODO State management?

main {
  flags %w(-h --help -V --version --list -v --verbose -vv -q --quiet --frozen --locked)
  option "--explain"
  option "--color", %w(auto always never)

  subcommand "help" {
    any %w(build check clean doc new init run test bench update search publish install)
  }

  subcommand "cat" {
    flags %w(-n -v)

    files
  }
}

RUBY_END
)
