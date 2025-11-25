#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [ "$#" -lt 3 ]
then
    echo "Usage: ts-get-auth-key <client_id> <client_secret> \"tag:tag1, tag:tag2\""
    exit 1
fi

tags=\"''${3//,/\", \"}\"

access_token=$(_out_/bin/ts-get-access-token "$1" "$2")

_curl_ "https://api.tailscale.com/api/v2/tailnet/-/keys" \
    -u "$access_token:" \
    --data-binary '
        {
        "capabilities": {
            "devices": {
            "create": {
                "reusable": true,
                "ephemeral": false,
                "preauthorized": true,
                "tags": ['"$tags"' ]
            }
            }
        },
        "expirySeconds": 1200,
        "description": "token created by nix script"
        }' | _jq_ -r '.key'