#!/bin/bash

. testutil.bash

# assert '(( 0 == 1 ))'

assert_out 'echo ok' <<EOF
oks
EOF

assert '(( 0 == 0 ))'
