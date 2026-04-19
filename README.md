# gh-activity-mirror

Mirrors daily GitHub contribution *counts* from the work account (`dominik-applifting`) to a private repo on the personal account (`domucchi`) so the personal contribution graph reflects real activity. Only counts are read — never repo names, branches, commit messages, or diffs.

## One-time setup

1. **Create the private mirror repo on the personal account.**
   ```sh
   gh auth switch --user domucchi
   gh repo create activity-mirror --private --clone=false
   ```

2. **Enable private contributions on the graph.**
   Visit https://github.com/settings/profile and turn on *"Include private contributions on my profile"*.

3. **Fill in `config.env`.**
   - `PERSONAL_EMAIL` must be verified on the `domucchi` account. The noreply address is recommended — get it with:
     ```sh
     gh auth switch --user domucchi
     gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"'
     ```
   - `PERSONAL_NAME` is already set.

4. **Make the script executable.**
   ```sh
   chmod +x sync.sh
   ```

## Usage

```sh
./sync.sh --dry-run   # preview: print day+count pairs that would be created
./sync.sh             # actually create backdated empty commits and push
```

First run backfills one year. Subsequent runs are incremental via `state.json`.

## How it works

1. `gh auth switch --user dominik-applifting`
2. GraphQL query for `contributionsCollection` over the sync window → `{date, count}` per day.
3. `gh auth switch --user domucchi`
4. For each day with `count > 0`: create N empty commits with `GIT_AUTHOR_DATE` set to that day (staggered seconds starting at noon UTC).
5. Push to `domucchi/activity-mirror`.
6. Update `state.json` with the new upper bound.

## Scheduling (optional)

To run weekly via launchd, drop a plist at `~/Library/LaunchAgents/com.domucchi.gh-activity-mirror.plist` pointing at `sync.sh`. Easiest alternative: a cron entry like `0 8 * * 1  /Users/domucchi/Code/scripts/gh-activity-mirror/sync.sh >> /tmp/gh-mirror.log 2>&1`.

## Caveats

- Only works because you're authenticated as the work user — the GraphQL `contributionsCollection` returns **private** contributions only to the viewer who owns them.
- "Include private contributions on my profile" must stay on, or private-repo commits won't show on the graph.
- If work policy restricts secondary use of activity data, think before running. The script only reads aggregate counts already visible to you, but the pattern can look odd in a compliance review — your call.
- Mirrored commits all have the message `"mirror activity"` and an empty tree. `git log` in the mirror repo makes the mechanism obvious to anyone who looks.
