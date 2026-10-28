---
title: rhino
date: 2026-09-02
tagline: Workflows as code. A mini Airflow in Go.
link: https://github.com/y0anfa/rhino
stack: [Go, YAML]
status: active
---

Rhino is a mini Airflow written in Go. A workflow is a YAML file: a trigger, a list of tasks, and the order to run them in.

It is the idea behind [Build the small tool](/build-the-small-tool/) applied to automation. The engine is small enough to read, for jobs that don't need a full platform.

- Triggers on a cron schedule or a webhook.
- Runs tasks concurrently, in the order you set, with timeouts and retries.
- Ships providers for shell, http, file, slack, discord, email, workflow and approval.
- Records every run and task execution, readable from a CLI, a TUI or a web dashboard.
- Validates every workflow before anything runs: unique task names, complete ordering, sane timeouts.

A minimal workflow:

```yaml
name: my-workflow
trigger:
  name: cron-trigger
  type: cron
  schedule: "0 */6 * * *"
tasks:
  - name: task1
    provider: shell
    params:
      command: echo
      args: ["hello"]
order:
  - [task1]
```
