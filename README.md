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
| `bin/sync-to-repo` | Copies the files above into another repository, for cloud sessions. |

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
   level for agents that set none, and keep synced copies of the rules (see below) from loading a
   second time:

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
subagent, and `/workflows` the model of each workflow agent.

## Cloud sessions

A cloud session starts from a fresh clone and sees nothing in `~/.claude`.

- Set `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` in the cloud environment's own environment variables. A
  value in a repository's `.claude/settings.json` is not applied there.
- Effort levels saved in `~/.claude/settings.json` do not reach a cloud session either. The four
  agent files keep their own levels, but the main session and any agent without an `effort` of its
  own run at their model's default, which is medium for Opus 5.5 and Sonnet 5.5. Either run
  `/effort xhigh` at the start of the session, or commit a `modelSettings` block with
  `claude-opus-5-5` and `claude-sonnet-5-5` at `xhigh` to the repository's
  `.claude/settings.json`. That file is read only in sessions with a single repository, and it
  sets the level for anyone else who runs Claude Code there.
- Copy the agents and rules into each repository that is used from the cloud, and commit them:

  ```sh
  bin/sync-to-repo ~/projects/some-repo
  bin/sync-to-repo --check ~/projects/some-repo   # exit 1 if a copy is missing or has drifted
  ```

  The copies land in `.claude/agents/` and `.claude/rules/delegation.md`. Edit the files here,
  never the copies: a repository's own copy of an agent wins over the one in `~/.claude`, in local
  sessions too, and the next sync replaces whatever the copy contained. After changing a file
  here, run the script again for every repository that has copies, and read `git diff` there
  before committing. A file deleted or renamed here is not removed from those repositories:
  delete the old copy by hand.

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
