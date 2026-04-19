# gh-activity-mirror

Mirror daily GitHub contribution **counts** from one account (e.g. a work
account with private repos you can't show) to a private repo on another
account, so the target account's contribution graph reflects your real
activity.

Only aggregate counts are read — never repo names, branch names, commit
messages, or diffs. The mirror repo contains only empty commits with the
message `"mirror activity"`.

## Requirements

- `gh` (GitHub CLI), `git`, `jq`, `bash`
- Both the source account and the target account signed into `gh`
  (`gh auth login`, once per account)

## Setup

```sh
./setup.sh
```

The script will:

1. Ask for the source and target GitHub usernames.
2. Verify both are authenticated with `gh`.
3. Create the private mirror repo on the target account (if it doesn't exist).
4. Fetch the target account's GitHub noreply email.
5. Write `config.env` with everything filled in.

Prefer to do it by hand? Copy `config.env.example` to `config.env` and edit
the values.

**One manual step setup can't do for you**: on the target account, turn on
*"Include private contributions on my profile"* at
<https://github.com/settings/profile>. Without it, commits in a private
repo won't show up on the graph.

## Usage

```sh
./sync.sh --dry-run   # preview: print day+count pairs that would be created
./sync.sh             # actually create backdated empty commits and push
```

First run backfills up to one year. Subsequent runs are incremental via
`state.json`.

## How it works

1. `gh auth switch` to the source account.
2. GraphQL query for `contributionsCollection` over the sync window
   → `{date, count}` per day.
3. `gh auth switch` to the target account.
4. For each day with `count > 0`: create N empty commits with
   `GIT_AUTHOR_DATE` set to that day (staggered seconds from noon UTC).
5. Push to the mirror repo.
6. Update `state.json` with the new upper bound.

## Scheduling (optional)

Weekly via cron:

```cron
0 8 * * 1  /absolute/path/to/gh-activity-mirror/sync.sh >> /tmp/gh-mirror.log 2>&1
```

Or a `launchd` plist on macOS pointing at `sync.sh`.

## Files

| File                  | Purpose                                        | Tracked? |
| --------------------- | ---------------------------------------------- | -------- |
| `sync.sh`             | The mirror logic                               | yes      |
| `setup.sh`            | Interactive config generator                   | yes      |
| `config.env.example`  | Documented config template                     | yes      |
| `config.env`          | Your local config (usernames, email)           | no       |
| `state.json`          | Tracks the last synced date                    | no       |
| `.mirror/`            | Local clone of the mirror repo                 | no       |

## Caveats

- The source account's private contributions are only returned by the
  GraphQL API to the viewer who owns them — that's why the script
  auth-switches to the source account to read counts.
- "Include private contributions on my profile" must stay on, or commits
  in the private mirror repo won't show on the target's graph.
- If the source account's policy restricts secondary use of activity data,
  think before running. The script only reads aggregate counts that are
  already visible to you, but the pattern can look odd in a compliance
  review — your call.
- Mirrored commits all have the message `"mirror activity"` and an empty
  tree. `git log` in the mirror repo makes the mechanism obvious to anyone
  who looks.

## License

MIT — see [LICENSE](LICENSE). Do whatever you want with it.
