#!/bin/bash

set -e
. mutil.sh

cat <<'__END_OF_OUTER_SCRIPT__' | cb
cat >>~/.profile <<'__EOF__'

#-------------------------------------------------
# Initialize ssh-agent

SSH_ENV="$HOME/.ssh/agent-environment"

function start_agent {
    echo "Initialising new SSH agent..."
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' >"$SSH_ENV"
    echo succeeded
    chmod 600 "$SSH_ENV"
    . "$SSH_ENV" >/dev/null
    /usr/bin/ssh-add; 
}

# Source SSH settings, if applicable

if [ -f "$SSH_ENV" ]; then
    . "$SSH_ENV" >/dev/null
    ps $SSH_AGENT_PID | grep ssh-agent$ >/dev/null || {
        start_agent
    } 
else
    start_agent 
fi
echo "ssh-agent initialized."
#-------------------------------------------------

__EOF__
__END_OF_OUTER_SCRIPT__
