# claude-agents

One place for the Claude Code subagents and delegation rules I use everywhere, so that local
sessions and cloud sessions do not drift apart.

The main session stays on Opus. Delegated work that Opus reads before anything rests on it
(searching, running tests, carrying out a fully specified plan) runs on Sonnet. Anything nobody
checks afterwards (planning, root-causing, design, review) stays on Opus.

## What is here

| Path | What |
|---|---|
| `agents/Explore.md` | Replaces the built-in Explore agent. Sonnet, medium effort, read-only. |
| `agents/test-runner.md` | Runs checks and reports failures; never fixes. Sonnet, low effort. |
| `agents/implementer.md` | Carries out a fully specified plan. Sonnet, high effort. |
| `agents/reviewer.md` | Reviews changes against their plan. Opus, xhigh effort, read-only. |
| `delegation.md` | Rules for the delegating agent: what goes to which agent, on which model. |
| `cloud/setup-script.sh` | Setup script for a cloud environment; fetches this repository and runs the installer. |
| `cloud/install.sh` | Installs the agents, the rules and `cloud/settings.json` into a cloud VM's `~/.claude`. |
| `cloud/test.sh` | Offline tests for the cloud scripts. Run it after any change; it also checks that `cloud/files.txt` lists every agent, which the last fetch route depends on. |
| `bin/check-setup` | Shows what is installed and which model and effort each agent of a session ran on. |
| `bin/sync-to-repo` | Copies the agents and rules into another repository instead (the alternative cloud route). |

## Local setup

1. Link the agents into the user configuration. Link the `agents/` folder, not the repository
   root:

   ```sh
   ln -sn ~/projects/claude-agents/agents ~/.claude/agents
   ```

   `-n` makes a second run fail instead of putting a link inside `agents/` itself. If
   `~/.claude/agents` already exists as a folder, move its files into `agents/` here first.

2. Import the rules from `~/.claude/CLAUDE.md` with a line of its own:

   ```
   @~/projects/claude-agents/delegation.md
   ```

3. In `~/.claude/settings.json`, make Sonnet the default for delegated agents, give it an effort
   level for agents that set none, and keep copies of the rules that `bin/sync-to-repo` put in a
   repository from loading a second time:

   ```json
   {
     "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet" },
     "modelSettings": { "claude-sonnet-5-5": { "effortLevel": "xhigh" } },
     "claudeMdExcludes": ["**/.claude/rules/delegation.md"]
   }
   ```

   If the file already has an `env` or `modelSettings` object (`/effort` creates `modelSettings`),
   add these entries inside it: a second key of the same name replaces the first, which would
   discard the levels saved for other models.

Restart Claude Code after this setup. A session that was already running may pick up the variable
and the agent files, but it keeps the effort levels it read at startup. `/context all` lists the
memory files that loaded, the import among them. `/tasks` shows the model of each running
subagent, and `/workflows` the model of each workflow agent. `bin/check-setup` prints the model
and effort every agent of the current session ran on.

## Cloud sessions

A cloud session runs in a new VM on a fresh clone and sees nothing in your `~/.claude`.

The setup script fetches this repository from GitHub without credentials, so the repository has
to be public there, with the `cloud/` folder on `main`, before the script is pasted anywhere.
This prints the file list once it is:

```sh
curl -fsSL https://raw.githubusercontent.com/nicholaskmitchell/claude-agents/main/cloud/files.txt
```

Each cloud environment you use (claude.ai/code, in the environment's settings) then needs two
things, with its network access left at Trusted (the default) or set to Full:

1. **Environment variables**: add `CLAUDE_CODE_SUBAGENT_MODEL=sonnet`. A value for it in a
   settings file is not applied in a cloud session.
2. **Setup script**: paste in the contents of `cloud/setup-script.sh`. When the environment is
   built, it fetches this repository and runs `cloud/install.sh`, which copies the agents to
   `~/.claude/agents` and the rules to `~/.claude/rules/delegation.md` inside the VM, and merges
   `cloud/settings.json` (the effort level for Sonnet agents that set none) into the VM's
   `~/.claude/settings.json`.

The environment keeps the result for about a week and runs the script again only when its text
changes. To pick up a change sooner: push it to GitHub, wait five minutes
(raw.githubusercontent.com can serve the previous version of a file for that long), change the
`rev:` number in the pasted script, and start a new session. A session that is already open keeps
what it started with. If the script cannot fetch or install the files, it leaves a note that
tells every session so, with the exit code of each route it tried.

To check a cloud session, have it start an agent or two, and then run:

```sh
curl -fsSL https://raw.githubusercontent.com/nicholaskmitchell/claude-agents/main/bin/check-setup | python3 -
```

The main session's own effort is not set by any of this: a cloud session starts at its model's
default unless you choose a level there.

If `bin/check-setup` shows `saved efforts {}` in a cloud session although the install status says
`ok`, something rewrote the VM's `~/.claude/settings.json` after the setup script ran. Claude Code
2.1.289 contains a feature that can do this: when a cloud session is started from a machine whose
user settings hold a `permissions` block or one of a few display settings, it copies those into
the VM as a new settings file.

This route depends on the VM reading its own `~/.claude`, which the documentation does not
promise. The alternative is to commit copies into each repository that is used from the cloud:

```sh
bin/sync-to-repo ~/projects/some-repo
bin/sync-to-repo --check ~/projects/some-repo   # exit 1 if a copy is missing or has drifted
```

The copies land in `.claude/agents/` and `.claude/rules/delegation.md`. Edit the files here, never
the copies: a repository's own copy of an agent wins over the one in `~/.claude`, in local
sessions too, and the next sync replaces whatever the copy contained. After changing a file here,
run the script again for every repository that has copies, and read `git diff` there before
committing. A file deleted or renamed here is not removed from those repositories: delete the old
copy by hand. Use one route or the other for a given repository; with both, a cloud session loads
the rules twice.

## How Claude Code behaves (checked against 2.1.289)

- `CLAUDE_CODE_SUBAGENT_MODEL` is a default, not an override. The order is the per-call `model`,
  then the agent file's `model`, then the variable, then the caller's model. Do not set
  `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`: it disables the first two.
- The built-in Explore and Plan agents say `model: inherit`, so the variable does not move them.
  `agents/Explore.md` is what puts exploration on Sonnet. Plan stays on the main model.
- The variable is also the default for workflow agents, so a workflow stage that should run on
  Opus has to say so.
- An agent that sets no `effort` runs at the level chosen for the session with `--effort` or
  `/effort <level>`, if there is one. Otherwise it runs at the level saved for its own model (the
  `modelSettings` entry above), not at the main session's, and failing that at its model's default
  (medium). `CLAUDE_CODE_EFFORT_LEVEL` overrides all of this and the agent files' `effort` too, so
  leave it unset.
- That `modelSettings` entry is the level `/effort` saves for Sonnet 5.5. A main session switched
  to Sonnet starts at it, and `/effort <level>` typed while on Sonnet overwrites it. It names one
  model version: add an entry when `sonnet` starts to resolve to a newer model.
- Native builds have no separate Grep and Glob tools; searching goes through Bash. The names stay
  in the `tools` lists for builds that do have them, and are ignored where they do not exist.
- Frontmatter keys must be spelled exactly (`disallowedTools`, `omitClaudeMd`). A misspelled key or
  an unknown tool name is ignored without a warning.

## Licence

MIT. See `LICENSE`.
