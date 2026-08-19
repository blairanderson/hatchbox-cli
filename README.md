# hatchbox — CLI for the Hatchbox.io API

A zero-dependency Ruby command-line tool for [Hatchbox](https://app.hatchbox.io). Every
list/get renders as a clean ASCII table (with `--json` for scripts), the API token is resolved
flexibly, and the account/app IDs you use most are remembered so you type them once.

```
$ hatchbox accounts list
+----+----------+---------+
| ID | Name     | Default |
+----+----------+---------+
| 1  | acme-inc | *       |
+----+----------+---------+
```

## Install

```sh
brew install blairanderson/tap/hatchbox
```

> This installs from the `blairanderson/homebrew-tap` repo. The CLI is pure Ruby stdlib —
> the formula only depends on `ruby`, nothing else.

Or run from a clone:

```sh
git clone https://github.com/blairanderson/hatchbox-cli
./hatchbox-cli/bin/hatchbox --version
```

## Authentication (flexible)

Create a token in Hatchbox under **API Tokens**. The CLI looks for it in this order (first wins):

1. `--token <TOKEN>` flag
2. `HATCHBOX_API_KEY`
3. `HATCHBOX_TOKEN`
4. `HATCHBOX_API_TOKEN`
5. `token:` in the config file

```sh
export HATCHBOX_API_KEY="your-token"
```

## Remembering your account & app

The most common flow is: list accounts → notice there's just one → keep using it forever.

- `hatchbox accounts list` — if you have exactly **one** account, it's auto-selected and cached
  as your default.
- `hatchbox accounts use <id>` — set the default account explicitly (for multi-account tokens).
- `hatchbox apps use <id>` — remember a default app, so commands like `hatchbox processes list`
  work without repeating the app id.

Defaults live in `~/.config/hatchboxcli/config.yml` (respects `XDG_CONFIG_HOME`). Precedence for
the account: `--account/-a` → `HATCHBOX_ACCOUNT_ID` → saved default → auto (when single).

## The app is detected from your git remote

Run any app command inside a repo that Hatchbox deploys and the CLI figures out which app
you mean — no id, no setup:

```sh
cd ~/dev/api
hatchbox processes list
# Detected app 42 (production-api) from origin acme/api (pinned via `git config hatchbox.app`).
```

An `<app_id>` is resolved in this order:

1. an explicit id on the command line
2. the **repo pin** — `git config hatchbox.app` (local to the repo, never committed)
3. the **origin remote**, matched against your apps' `repo_path` — one match wins and is
   pinned so later commands skip the API lookup; several matches are tie-broken by the
   current git branch (staging vs production), and a remaining tie asks you to pin one
4. the saved `default_app` from `hatchbox apps use <id>`

Useful extras:

- `hatchbox whoami` — show the current account and the app connected to this directory,
  plus *how* it was resolved. Read-only.
- `hatchbox apps use` (no id) — detect the app from the origin remote and pin it now.
- `git config hatchbox.app <id>` — pin (or re-pin) by hand, e.g. to pick staging.

## Commands

Every command accepts the global flags `--json`, `--token`, `--account/-a`, `--no-color`.

| Group | Commands |
|-------|----------|
| `whoami` | show current account + the app for this directory |
| `accounts` | `list`, `use <id>`, `current` |
| `apps` | `list`, `get <id>`, `create`, `update <id>`, `deploy <id> [--sha]`, `restart <id>`, `auto-deploy enable\|disable <id>`, `use [<id>]` |
| `env` | `list <app_id>`, `set <app_id> KEY=VAL...`, `unset <app_id> KEY...` |
| `master-key` | `[app_id] [--yes]` — set `RAILS_MASTER_KEY`, app found from your git remote |
| `processes` | `list <app_id>`, `get <app_id> <id>`, `restart <app_id> <id>` |
| `clusters` | `list`, `get <id>` |
| `servers` | `list <cluster_id>`, `get <cluster_id> <id>` |
| `domains` | `list <app_id>`, `get`, `add`, `update`, `remove` |
| `git-providers` | `list` |
| `db-clusters` | `list` |
| `databases` | `list <db_cluster_id>`, `get`, `create`, `update`, `app-list <app_id>`, `attach`, `detach`, `backup-latest <db_id>`, `backup-trigger <db_id>` |
| `logs` | `get <log_id>`, `watch <log_id>` |
| `config` | `path`, `show` |

Async actions (`deploy`, `restart`, `backup-trigger`) return a **log id**. Follow it live:

```sh
hatchbox apps deploy 42 --sha abc123
hatchbox logs watch 99          # polls until completed / failed / aborted
```

Env vars are **write-only** — the API exposes no read endpoint at all, so there is no `env list`. Set and unset them here; read them in the Hatchbox web UI.

### RAILS_MASTER_KEY

The Heroku equivalent is `heroku config:set RAILS_MASTER_KEY=$(cat config/credentials/production.key)`.
Here it is one command with no arguments. Run it inside your Rails repo:

```sh
hatchbox master-key
```

```
Matched app 42 (production-api) — acme/api

App 42 (production-api)
  repo      acme/api
  key file  config/credentials/production.key

Overwrite RAILS_MASTER_KEY on app 42? [y/N] y
Set RAILS_MASTER_KEY on app 42 (production-api) from config/credentials/production.key.
Run `hatchbox apps restart 42` (or deploy) to apply it.
```

What it does:

1. reads `git remote get-url origin`
2. finds the app in your account whose `repo_path` is that repo
3. reads `config/credentials/production.key`, or `config/master.key` if the first is absent
4. asks you to confirm, then sets `RAILS_MASTER_KEY`

If two apps deploy the same repo (staging and production, say), it lists them and you pick one:
`hatchbox master-key 43`. An explicit app id is still checked against your git remote, so the
command **stops on a mismatch** and you cannot push one app's key to another app.

Add `--yes` in scripts and CI. The key never appears in your shell history or in `ps` output.
Env vars apply on the next deploy or restart, so finish with `hatchbox apps restart 42`.

### JSON output

```sh
hatchbox apps list --json | jq '.[].id'
```

## Examples

```sh
hatchbox whoami                         # current account + the app for this directory
hatchbox accounts list
hatchbox apps list
hatchbox processes list                 # inside a deployed repo: app auto-detected + pinned
hatchbox apps use 42                    # or set a default app for everywhere else
hatchbox env set 42 RAILS_ENV=production SECRET_KEY=xyz
hatchbox env unset 42 OLD_FLAG
hatchbox master-key                     # set RAILS_MASTER_KEY (run inside the Rails repo)
hatchbox apps deploy 42
hatchbox databases backup-trigger 7
```

## Development

```sh
# run the test suite (stdlib minitest, no gems)
ruby -Itest -Ilib -e 'Dir["test/test_*.rb"].each { |f| require File.expand_path(f) }'

# point the CLI at the bundled mock API for local experiments
ruby eval/mock_server.rb eval/scenario.json &
export HATCHBOX_API_URL=http://127.0.0.1:4567/api/v1
export HATCHBOX_API_KEY=eval-token-abc123
./bin/hatchbox accounts list
```

The `HATCHBOX_API_URL` env var overrides the base URL (used by tests and the eval harness).

## Releasing (Homebrew)

1. Tag a release: `git tag v0.1.0 && git push --tags`.
2. GitHub creates the source tarball at `.../archive/refs/tags/v0.1.0.tar.gz`.
3. `shasum -a 256` the tarball and update `url` + `sha256` in the tap's `Formula/hatchbox.rb`.

## LLM eval

`eval/` contains a graded spec (`EVAL.md` + `rubric.yml`) for an agent that coordinates an AWS
Postgres upgrade using this CLI, plus a mock server and a simulated user. See
[`eval/README.md`](eval/README.md).

## License

MIT
