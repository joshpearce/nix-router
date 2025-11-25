#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [ "$#" -lt 3 ]
then
    echo "Usage: ts-delete-node <client_id> <client_secret> <node name>"
    exit 1
fi

access_token=$(_out_/bin/ts-get-access-token "$1" "$2")

ts_ids=$(_curl_ 'https://api.tailscale.com/api/v2/tailnet/-/devices' -u "$access_token:" | _jq_ -r ".devices[]? | select(.hostname == \"$3\") | .id")

while IFS= read -r ts_id; do
    _curl_ -X DELETE "https://api.tailscale.com/api/v2/device/$ts_id" -u "$access_token:"
done <<< "$ts_ids"