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

## Commands

Every command accepts the global flags `--json`, `--token`, `--account/-a`, `--no-color`.

| Group | Commands |
|-------|----------|
| `accounts` | `list`, `use <id>`, `current` |
| `apps` | `list`, `get <id>`, `create`, `update <id>`, `deploy <id> [--sha]`, `restart <id>`, `auto-deploy enable\|disable <id>`, `use <id>` |
| `env` | `list <app_id>`, `set <app_id> KEY=VAL...`, `unset <app_id> KEY...` |
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

Env var values are **write-only** — the API never returns them, so `env list` shows names only.

### JSON output

```sh
hatchbox apps list --json | jq '.[].id'
```

## Examples

```sh
hatchbox accounts list
hatchbox apps list
hatchbox apps use 42
hatchbox processes list                 # uses default app 42
hatchbox env set 42 RAILS_ENV=production SECRET_KEY=xyz
hatchbox env unset 42 OLD_FLAG
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
