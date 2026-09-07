# Router deployment from its on-host checkout

The router is deployed from its checkout at `/home/josh/code/router`. Do not use
`deploy-flake` for this host. Develop and validate in the local Git repository,
commit and push the reviewed change, then fetch and fast-forward the clean router
checkout to that exact commit. Build and activate through this repository's
Makefile with `sudo` inside a named tmux session.

Router activation can interrupt household routing, DNS, DHCP, firewall behavior,
and the SSH/Tailscale control path. A tmux session preserves the on-router shell
and build process across a client disconnect; it does not provide console access
or survive a router reboot. Establish the applicable recovery path before a risky
network change.

## Prepare locally

Work on a focused branch and preserve unrelated changes:

```sh
git status --short --branch
git switch -c ISSUE-BRANCH
# edit and test
git diff --check
git add REVIEWED-PATHS
git commit
git push -u origin ISSUE-BRANCH
```

Do not push decrypted `private/config.nix`, credentials, or diagnostic output.
The committed public revision and encrypted inputs are the deployment source.

## Preflight on the router

Connect through the established alias, start or attach a task-specific tmux
session, and perform every subsequent deployment command inside it:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=10 nix-router
tmux new-session -A -s router-deploy
```

Inside tmux, require a clean checkout and record the rollback closure before
fetching. Replace the placeholders with literal reviewed values:

```sh
cd /home/josh/code/router
test -z "$(git status --porcelain)"
old_commit=$(git rev-parse HEAD)
old_system=$(readlink /run/current-system)
printf 'old_commit=%s\nold_system=%s\n' "$old_commit" "$old_system"

git fetch origin refs/heads/ISSUE-BRANCH
git merge-base --is-ancestor REVIEWED-COMMIT FETCH_HEAD
git merge --ff-only REVIEWED-COMMIT
test "$(git rev-parse HEAD)" = REVIEWED-COMMIT
test -z "$(git status --porcelain)"
```

Keep the old closure path in the tmux scrollback and the deployment record. Do
not use `git pull`, do not deploy an uncommitted tree, and do not confuse checkout
HEAD with the running generation.

## Validate and activate

Run the repository checks and build on the x86_64-linux router, then switch only
under explicit authorization:

```sh
sudo make check
sudo make build
sudo make switch
```

The Makefile decrypts the committed private input using the router host key and
passes `--override-input private path:./private`. Its decrypt target must fail
closed: decrypt to a mode-0600 temporary file and atomically replace
`private/config.nix` only after success. Never use `make diff-config` in captured
automation because it can print private configuration.

`make test` is not a read-only validation; it activates a NixOS configuration.
Do not substitute it for `make check` or `make build`.

## Postconditions and rollback

After `make switch`, verify from inside tmux before detaching:

```sh
readlink /run/current-system
systemctl --failed --no-pager
systemctl is-active network-online.target tailscaled.service
getent ahostsv4 nas.home homeassistant.home
ip -4 route show default
```

Also verify the services and external signals affected by the specific change.
Reconnect through a fresh SSH session before declaring the access path healthy.
Record the deployed commit, new closure, UTC time, checks, and remaining unknowns.

If an authorized rollback condition is met and the tmux session still works,
reactivate the recorded closure directly:

```sh
sudo "$old_system/bin/switch-to-configuration" switch
```

Then repeat the network and service postchecks. Source rollback is separate:
fast-forward or revert through reviewed Git history after service is restored.
Code rollback does not reverse Route53, database, filesystem, or other external
state changes. If SSH and tmux are both unreachable, use the pre-established
console or boot recovery path; do not improvise firewall or routing changes.
