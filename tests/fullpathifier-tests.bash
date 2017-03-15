#!/bin/bash

. testutil.bash

# Move to the script parent directory
cd ${0%/*}/..

root=$(pwd)

echo "root=$root"

run() {
  fullpathifier <<'EOF' | sed -e "s!$root![root]!g"
a b c
bbc def IsFile.pm
c
IsFile.pm IsFile.pl
/tmp
fullpathifier-tests.bash
Entering directory `tests'
IsFile.pm IsFile.pl
fullpathifier-tests.bash
EOF
}

assert_out run <<'EOF'
CWD=[root]/
a b c
bbc def [root]/IsFile.pm
c
[root]/IsFile.pm IsFile.pl
/tmp
fullpathifier-tests.bash
Entering directory `tests'
CWD=[root]/tests/
IsFile.pm IsFile.pl
[root]/tests/fullpathifier-tests.bash
EOF
