
set +e # Don't use set -e, which may mask real bugs in tests.

declare -i _num_successes=0
declare -i _num_failures=0
declare -i _need_newline_before_failure=0

_at_exit() {
  echo ""
  echo "----"
  echo "$(( $_num_successes + $_num_failures )) tests executed, $_num_successes passed, $_num_failures failed." 1>&2
  (( $_num_failures == 0 && $_num_successes > 0 ))
  exit $?
}

succeed() {
  _num_successes=$(( $_num_successes + 1 ))
  echo -n "."
  _need_newline_before_failure=1
}

fail() {
  if (( $_need_newline_before_failure )) ; then
    echo
  fi
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
  fail
  {
    echo "- Test '$exp' failed at:"
    caller | sed -e 's/^/    /'
  } 1>&2
  return 0
}

assert_out() {
  out=$(wdiff -n \
      -w $'\033[30;41m' -x $'\033[0m' \
      -y $'\033[30;42m' -z $'\033[0m' \
      <("$@") <(cat))
  local rc=$?
  if (( $rc == 0 )) ; then
    succeed
  else
    {
      echo "- Test '$exp' failed at:"
      caller | sed -e 's/^/    /'
      echo "diff was:"
      echo "$out"
    } 1>&2
    fail
  fi
}

trap _at_exit EXIT
