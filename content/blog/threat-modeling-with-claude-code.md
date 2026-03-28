---
date: '2026-03-28'
title: 'Threat modeling with Claude Code'
draft: false
tags: ["threat-modeling", "ai", "security"]
---

Threat modeling is one of those practices that everyone agrees is important and almost no one does consistently. The ceremony around it -- dedicated meetings, specialized tooling, security team bottlenecks -- makes it easy to skip when you're shipping under pressure. And when it does happen, the quality varies wildly depending on who's in the room and how much context they have.

We wanted to change that. So we built a `threat-model` skill for our internal Claude Code plugin that brings STRIDE-based threat modeling directly into the developer workflow.

## The problem with traditional threat modeling

Most threat modeling happens too late, too rarely, or not at all. The typical process looks something like this: a team finishes designing a feature, schedules a meeting with the security team, walks through an architecture diagram on a whiteboard, and produces a document that may or may not get revisited. If you're lucky, this happens before code is written. More often, it happens after -- or never.

This was already a problem. But the rise of agentic coding made it urgent. When developers are shipping faster with AI assistance, security review needs to keep pace. You can't have agents generating code at high velocity while threat modeling stays a quarterly ritual. The gap between "code written" and "threats assessed" just keeps growing.

We needed threat modeling to be something that happens *during* development, not after it. And it needed to be low-friction enough that developers would actually use it.

## How the skill works

The `threat-model` skill is a slash command that developers can invoke directly in Claude Code. Other skills and workflows in our plugin also suggest running it at relevant moments -- for example, when a feature touches authentication, data storage, or external integrations.

The interaction follows a structured flow:

**1. Feature understanding and risk assessment.** The skill first builds context about what the developer is working on. It reads the codebase, understands the architecture, and asks targeted questions about the feature. Based on this, it assigns a risk level. Not every change needs a full threat model -- a CSS refactor and a new authorization architecture have very different risk profiles.

**2. STRIDE-based threat identification.** For high-risk features, the skill walks through each STRIDE category systematically:

- **Spoofing** -- Can an attacker impersonate a legitimate user or system?
- **Tampering** -- Can data be modified in transit or at rest?
- **Repudiation** -- Can actions be performed without accountability?
- **Information Disclosure** -- Can sensitive data leak to unauthorized parties?
- **Denial of Service** -- Can the feature be abused to degrade availability?
- **Elevation of Privilege** -- Can an attacker gain unauthorized access levels?

For each category, the skill asks the developer context-specific questions. These aren't generic security checklists. Because the skill has access to the codebase and understands the architecture, it can ask pointed questions about the actual implementation: "This endpoint accepts user-supplied file paths -- how are you validating those inputs?" or "The new queue consumer doesn't authenticate messages from the broker -- is this intentional?"

**3. Risk flagging and treatment suggestions.** Based on the answers, the skill identifies concrete risks and suggests treatments. These might be code changes, architectural adjustments, or items to flag for deeper review with the security team. The output is actionable, not a wall of theoretical vulnerabilities.

**4. Structured output.** When the analysis is complete, the skill writes a threat model report to Notion via MCP and creates Linear issues for each recommended treatment -- ready to be triaged and prioritized alongside the rest of the team's work. If the MCP integrations aren't available (local development, restricted environments), it falls back to generating Markdown files instead. Either way, the output is durable and trackable, not lost in a terminal session.

This matters more than it sounds. One of the failure modes of traditional threat modeling is that findings live in a slide deck or a wiki page that nobody revisits. By pushing treatments directly into the issue tracker, they enter the same workflow as any other engineering task. They get assigned, estimated, and shipped -- or explicitly deprioritized with a paper trail.

## Making STRIDE practical with LLM context

STRIDE has been around since the late 1990s. It's well-understood and battle-tested. But applying it effectively requires deep context about the system being analyzed -- context that's expensive to build in a traditional threat modeling session.

This is where Claude Code's access to the codebase changes the equation. The skill doesn't start from a blank whiteboard. It starts with the code. It can trace data flows, identify trust boundaries, and understand how components interact. The developer fills in the gaps that the code doesn't make obvious: business context, deployment environment, compliance requirements, expected user behavior.

The result is a threat model that's grounded in the actual implementation, not an idealized architecture diagram that may have drifted from reality months ago.

## The real shift: developer security thinking

The most interesting outcome wasn't the threat models themselves. It was watching developers internalize security thinking.

When you run through STRIDE interactively a few times, the categories start to stick. Developers begin asking themselves "what's the spoofing risk here?" or "can this be tampered with?" before they even invoke the skill. The tool becomes a training mechanism, not just an assessment tool.

This is the shift-left promise actually delivered. Not "we moved the security gate earlier in the pipeline" but "developers now think about threats as they design." The skill lowers the activation energy for threat modeling enough that it becomes a natural part of feature development rather than an external checkpoint.

## Design decisions worth noting

A few choices shaped how the skill turned out:

**Risk-gated depth.** Not every change gets the full treatment. The initial risk assessment determines how deep the analysis goes. This prevents fatigue -- developers don't get interrogated about STRIDE categories when they're fixing a typo in a log message.

**Integrated, not isolated.** The skill lives inside the same Claude Code environment developers already use. It's not a separate tool they need to context-switch into. Other skills can suggest running it, creating natural entry points rather than relying on developers to remember.

**Interactive over automated.** We deliberately chose an interactive Q&A approach over fully automated scanning. Automated tools generate findings. Interactive sessions generate understanding. The developer has to engage with each threat category, which builds the muscle memory that makes future development more security-aware.

**Codebase-aware.** Because the skill can read the actual code, its questions are specific and relevant. Generic security questionnaires get ignored. Questions about your actual implementation get answered.

## Where this is heading

This is still early. The skill handles feature-level threat modeling well, and it's already growing in interesting directions. Because reports live in Notion, the skill can suggest revisiting legacy threat models when a developer is working on a related feature. A threat model written six months ago against a different version of the codebase may have gaps -- the skill can pull up that report, walk through it against the current implementation, and flag what's changed. Threat models become living documents rather than point-in-time snapshots.

There's more room to grow: aggregating patterns across teams to identify systemic risks, feeding findings back into automated security testing, and using historical threat models as training signal to improve the skill's risk assessment over time.

The broader principle is worth watching, though. As AI coding assistants become standard, the security practices around them need to evolve in parallel. Threat modeling that lives inside the development workflow -- not beside it -- is one piece of that puzzle.

If your team is struggling with threat modeling adoption, consider meeting developers where they already are. The best security practice is the one that actually gets done.
