#!/bin/sh

# Ensure exactly one argument is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <https|ssh>"
    exit 1
fi

PROTO="$1"

# Validate argument
if [ "$PROTO" != "https" ] && [ "$PROTO" != "ssh" ]; then
    echo "Error: Argument must be either 'https' or 'ssh'"
    exit 1
fi

# Repos (owner/repo)
REPOS="
LordDarkula/linux
LordDarkula/colloid
matte21/tinker-linux
"

for REPO in $REPOS; do
    NAME=$(basename "$REPO")

    if [ "$PROTO" = "https" ]; then
        URL="https://github.com/$REPO.git"
    else
        URL="git@github.com:${REPO}.git"
    fi

    echo "Cloning $NAME from $URL ..."
    git clone "$URL"
done

