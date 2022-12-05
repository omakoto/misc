#!/bin/bash

cd $(dirname $0)

curl https://raw.github.com/git/git/master/contrib/completion/git-completion.bash > git-completion.bash
