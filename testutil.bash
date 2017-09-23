
set +e # Don't use set -e, which may mask real bugs in tests.

. mutil.sh

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
  {
    bred -- "- $* at:"
    local frame=0
    {
      while caller $frame; do
        ((frame++));
      done
    } | sed -e 's/^/  /'
    echo
  } 1>&2
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

assert_out() {
  local use_wdiff=1
  if [[ "$1" == "-d" ]] ; then
    use_wdiff=0
    shift
  fi

  local rc
  if (( $use_wdiff )) ; then
    local wdiff_opts=""
    if iscon 2 ; then
      wdiff_opts='-w '$'\033[30;41m'' -x '$'\033[0m'' -y '$'\033[30;42m'' -z '$'\033[0m'
    fi
    out=$(wdiff -n $wdiff_opts <("$@") <(cat))
    rc=$?
  else
    local diff_opts=""
    if iscon 2 ; then
      diff_opts='--color=always'
    fi
    out=$(diff -c $diff_opts <("$@") <(cat))
    rc=$?
  fi
  if (( $rc == 0 )) ; then
    succeed
  else
    fail "Diff test failed"
    {
      byellow "Diff was:"
      echo "$out"
    } 1>&2
  fi
}

#trap _at_exit EXIT
function done_testing() {
  _at_exit # Note this actually calls exit()
}
