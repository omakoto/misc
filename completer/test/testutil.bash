
set +e # Don't use set -e, which may mask real bugs in tests.

declare -i _num_successes=0
declare -i _num_failures=0
declare -i _need_newline_before_failure=0

diff_opts=""

if diff --help 2>/dev/null| grep -q -- "--color" ; then
  diff_opts='--color=always'
fi

succeed() {
  _num_successes=$(( $_num_successes + 1 ))
  echo -n "."
  _need_newline_before_failure=1
}

fail() {
  if (( $_need_newline_before_failure )) ; then
    echo
  fi
  {
    echo "- $* at:"
    local frame=0
    {
      while caller $frame; do
        ((frame++));
      done
    } | sed -e 's/^/  /'
    echo
  }
  _num_failures=$(( $_num_failures + 1 ))
  _need_newline_before_failure=0
}

# eval the entire arguments and check the status code.
assert() {
  local exp="$*"

  eval "$exp"
  local rc=$?
  if (( $rc == 0 )) ; then
    succeed
    return 0
  fi
  fail "Test '$exp' failed"
  return 0
}

# Execute "$@", and diff its output with stdin.
# Options:
#  -s  Sort outputs before comparing.
assert_out() {
  local filter=cat
  local OPTIND

  while getopts "s" opt; do
    case "$opt" in
      s) filter=sort ;;
    esac
  done
  shift $(($OPTIND - 1))

  local rc
  out=$(diff -c $diff_opts <("$@" | $filter) <($filter))
  rc=$?
  if (( $rc == 0 )) ; then
    succeed
  else
    fail "Diff test failed"
    echo "Diff was:"
    echo "$out"
  fi
}

# Call this at the end of the test.
function done_testing() {
  echo ""
  echo "----"
  echo "$(( $_num_successes + $_num_failures )) tests executed, $_num_successes passed, $_num_failures failed." 1>&2
  (( $_num_failures == 0 && $_num_successes > 0 ))
  exit $?
}
