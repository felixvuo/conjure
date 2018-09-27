#!/bin/bash

set -o errexit
set -o nounset

export BIN_DIR=${BIN_DIR:-${HOME}/.local/bin}

rm -rf ~/tmp-install-minion
mkdir ~/tmp-install-minion
pushd ~/tmp-install-minion

OS=$(uname)

if [ "$OS" == "Darwin" ]; then
    wget --no-check-certificate -c https://savilerow.cs.st-andrews.ac.uk/savilerow-1.7.0RC-mac.tgz
    tar -xvzf savilerow-1.7.0RC-mac.tgz
    mv savilerow-1.7.0RC-mac/bin/minion ${BIN_DIR}/minion
elif [ "$OS" == "Linux" ]; then
    wget --no-check-certificate -c https://savilerow.cs.st-andrews.ac.uk/savilerow-1.7.0RC-linux.tgz
    tar -xvzf savilerow-1.7.0RC-linux.tgz
    mv savilerow-1.7.0RC-linux/bin/minion ${BIN_DIR}/minion
else
    echo "Cannot determine your OS, uname reports: ${OS}"
    exit 1
fi

echo "minion executable is at ${BIN_DIR}/minion"
ls -l ${BIN_DIR}/minion
popd
rm -rf ~/tmp-install-minion

