<!-- Canonical copy: the claude-agents repository. Edit it there and run bin/sync-to-repo; do not edit a copy. -->
## Delegation: which model does what

These rules apply whenever you hand work to another agent, through the Agent tool or a workflow script. If you are not delegating, skip this section.

The user has split the work between two tiers of model, and the split holds with ultracode on: ultracode asks for more agents and more verification, not for a bigger model on mechanical stages. Which models make up the two tiers depends on your own model: the one your system prompt says you are powered by, not the one the session was configured with if the two differ.

| Your model | Upper tier | Lower tier |
|---|---|---|
| Mythos | Mythos | Opus |
| Fable | Fable | Opus |
| Opus, any other model, or not sure | Opus | Sonnet |

- **The lower tier does work that the upper tier reads before anything rests on it**: locating code, gathering sources, running tests and builds, applying a change you have fully specified.
- **The upper tier does anything nobody checks afterwards**: planning, architecture and design, root-causing a failure whose cause is unknown, reviewing a change. Make these decisions yourself; an agent that helps with them must run on the upper tier.

### Which agent

Use these by name, as `subagent_type` or as a workflow `agentType`:

| Work | Agent | Runs on |
|---|---|---|
| Find or map code | `Explore` | lower tier |
| Run tests, builds, linters | `test-runner` | lower tier |
| Change files to a fully specified plan | `implementer` | lower tier |
| Review a change | `reviewer` | upper tier |
| Any other work that judges: plan, design, diagnose, verify, score, synthesise | `analyst` | upper tier |

- Give `implementer` only a fully specified plan: the files, the change in each, the checks that must pass and what to leave alone, with no design decision left open (names, signatures and error behaviour are stated). If you cannot write that yet, or `implementer` stops over a problem with the plan, finish the planning yourself.
- An agent that changes files is always `implementer`, in workflow scripts too. Send every change an agent made to `reviewer` before you report the work as done: once, when the work is complete, as the whole change with the plan as it now stands.
- Give any agent that judges rather than fetches, runs or applies to `analyst`: one that plans, designs, diagnoses a failure, looks for defects, verifies or refutes, scores, synthesises or asks what is missing. That includes the finder and verify agents that a review skill such as `/code-review` has you start, wherever the skill would use `general-purpose` or names no agent type. When unsure, use `analyst`.
- Treat a lower-tier agent's report as a claim. Before a plan, a fix or a conclusion rests on it, read the lines it cites or have `analyst` verify them. A report of absence ("not found", "no other callers", "all passed") is only as good as the searches or commands it lists; when a decision rests on one, run the deciding search yourself.

### Model and effort

The agent files hold the default split: `Explore`, `test-runner` and `implementer` say `model: sonnet`, while `reviewer` and `analyst` say `model: inherit` and run on your model, as the built-in `Plan` agent does. A `model` you pass on the call overrides the file.

- On Mythos or Fable, pass `opus` on every call to `Explore`, `test-runner` and `implementer`. On any other model, pass them no model, or they would run on Opus at their own lower effort. The one exception is an escalated `implementer` step, below.
- On Opus, Mythos or Fable, pass no model to `reviewer` or `analyst`. On any other model, pass `opus` to them.
- Use `general-purpose`, and workflow `agent()` calls that have no `agentType`, only for lower-tier work, and name the lower tier on every such call: `sonnet`, or `opus` on Mythos or Fable. Upper-tier work goes to `analyst`, never to these: the Agent tool cannot name Mythos (its `model` takes only `sonnet`, `opus`, `haiku` and `fable`), and where `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` is set, as it should be, an agent with no model runs on Sonnet, not on your model. The workflow authoring reference's advice to omit `model` does not apply here.
- Escalate the step, not the task: give `implementer` the upper tier when that step itself touches concurrency, security or design across modules, or when a lower-tier agent has already got that step wrong once. Pass `opus` on Opus or any other model, and `fable` on Fable. On Mythos no model name reaches Mythos, and Fable is not part of the Mythos split, so make that change yourself and send it to `reviewer` as you would an agent's change. An `implementer` that stops over a problem with the plan has not failed: fix the plan and send it to the lower tier again.
- Workflow `effort`: leave it out with an `agentType`, because passing it overrides the agent file. Otherwise always pass it: `'xhigh'`, the user's default, or `'low'` for a stage that only runs a command. `meta.phases[].model` is display only.
- A `fork` always runs on your model at your effort, so it is the most expensive way to delegate. Fork only when a fresh agent could not do the work without this conversation. Where the Agent tool description suggests forking research or a survey, use `Explore` or a lower-tier `general-purpose` agent.
