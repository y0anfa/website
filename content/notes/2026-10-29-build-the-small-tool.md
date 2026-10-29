---
title: Build the small tool
date: 2026-10-29
description: A questionnaire agent on Slack, built with Claude Code in three days, and the rule I use to decide when to build instead of buy.
---

Security questionnaires sit in the middle of every deal. A prospect sends a spreadsheet of questions about encryption, access reviews and incident response. Sales forwards it to security. Someone in security answers questions they have answered many times before, and the deal waits.

We first used the questionnaire feature of our compliance platform. It did the job on paper. In practice it took time to set up, and more time to keep its answers current. It was one more system to feed, and sales still had to go through us.

So we built a small tool instead: an agent that sales talks to directly on Slack. They ask it a question, or drop in a questionnaire, and it fills in the answers from a knowledge base we keep on GitHub. The knowledge base is plain markdown in a repository, so every answer has a history and a diff.

I built the first version with Claude Code in three days. Since then it takes two to four hours a week to improve it and handle the edge cases.

There were plenty of those. The first version didn't read every format sales received, and some questions it couldn't answer at all. Each gap had one of two fixes: teach it the format, or write the missing answer down. Either way the fix was ours to make, and we didn't have to wait for anyone.

## Why the small tool won

It works where people already are. Sales doesn't open another app or file a ticket. They ask in Slack.

Its knowledge is ours. The answers live in a repository we already maintain, not in a vendor's library.

It does one job. I know how it behaves, and when it is wrong I know where to look.

## When I buy instead

This is not an argument against vendors. When the engine is the real value, I'd rather trust a vendor that puts its resources into that engine. I won't out-build a team whose whole product is that engine.

A questionnaire tool is different. Reading a spreadsheet and finding the right answer is no longer the hard part: a model does it well. The value is in the answers, and those were always ours. When the engine is a commodity and the knowledge is yours, build.

## Where the time goes

Claude Code changed the math. Three days to a working version is less time than most vendor evaluations take. A few hours a week keeps it fitting exactly what sales needs.

Look at the hours in your week that go to the same answers, the same checks and the same forms. Some of them are a small tool waiting to be built, and it might take three days.
