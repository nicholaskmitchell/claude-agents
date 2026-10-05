<!-- Canonical copy: the claude-agents repository. Edit it there and run bin/sync-to-repo; do not edit a copy. -->
## Delegation: which model does what

These rules apply whenever you hand work to another agent, through the Agent tool or a workflow script. If you are not delegating, skip this section.

The user has split the work between two models, and the split holds with ultracode on: ultracode asks for more agents and more verification, not for a bigger model on mechanical stages.

- **Sonnet does work that Opus reads before anything rests on it**: locating code, gathering sources, running tests and builds, applying a change you have fully specified.
- **Opus does anything nobody checks afterwards**: planning, architecture and design, root-causing a failure whose cause is unknown, reviewing a change. Make these decisions yourself; an agent that helps with them must run on Opus.

### Which agent

Use these by name, as `subagent_type` or as a workflow `agentType`:

| Work | Agent | Runs on |
|---|---|---|
| Find or map code | `Explore` | Sonnet |
| Run tests, builds, linters | `test-runner` | Sonnet |
| Change files to a fully specified plan | `implementer` | Sonnet |
| Review a change | `reviewer` | Opus |

- Give `implementer` only a fully specified plan: the files, the change in each, the checks that must pass and what to leave alone, with no design decision left open (names, signatures and error behaviour are stated). If you cannot write that yet, or `implementer` stops over a problem with the plan, finish the planning yourself.
- An agent that changes files is always `implementer`, in workflow scripts too. Send every change an agent made to `reviewer` before you report the work as done: once, when the work is complete, as the whole change with the plan as it now stands.
- Treat a Sonnet agent's report as a claim. Before a plan, a fix or a conclusion rests on it, read the lines it cites or have an Opus agent verify them. A report of absence ("not found", "no other callers", "all passed") is only as good as the searches or commands it lists; when a decision rests on one, run the deciding search yourself.

### Model and effort

Name a model on every `general-purpose` Agent call and every workflow `agent()` call that has no `agentType`: `sonnet` or `opus`. The workflow authoring reference's advice to omit `model` does not apply here: where `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` is set, as it should be, an agent with no model runs on Sonnet, not on your model.

- Pass `opus` to any agent that judges rather than fetches, runs or applies: one that plans, designs, diagnoses a failure, looks for defects, verifies or refutes, scores, synthesises or asks what is missing. That includes the finder and verify agents that a review skill such as `/code-review` has you start. When unsure, pass `opus`.
- Escalate the step, not the task: pass `opus` to `implementer` as well when that step itself touches concurrency, security or design across modules, or when a Sonnet agent has already got that step wrong once. An `implementer` that stops over a problem with the plan has not failed: fix the plan and send it to Sonnet again. Never pass a model to `Explore` or `test-runner`; they would run on Opus at their own lower effort.
- Workflow `effort`: leave it out with an `agentType`, because passing it overrides the agent file. Otherwise always pass it: `'xhigh'`, the user's default, or `'low'` for a stage that only runs a command. `meta.phases[].model` is display only.
- A `fork` always runs on your model at your effort, so it is the most expensive way to delegate. Fork only when a fresh agent could not do the work without this conversation. Where the Agent tool description suggests forking research or a survey, use `Explore` or a Sonnet agent.
