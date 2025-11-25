#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [ "$#" -lt 2 ]
then
    echo "Usage: ts-get-access-token <client_id> <client_secret>"
    exit 1
fi

client_id=$1
client_secret=$2

result=$(_curl_ -X POST -u "$client_id:$client_secret" -d "grant_type=client_credentials" -d "scopes=devices tag:workloads" https://api.tailscale.com/api/v2/oauth/token)
token=$(echo "$result" | _jq_ -r '.access_token')
echo "$token"