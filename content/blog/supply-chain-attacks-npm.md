---
title: "Supply Chain Attacks in npm: What We Keep Getting Wrong"
date: 2026-03-15
tags: ["security", "supply-chain", "nodejs"]
subtitle: "Lockfiles won't save you. Here's what will."
---

The npm ecosystem moves fast and breaks things — sometimes on purpose. Over the past two years, supply chain attacks targeting JavaScript packages have become more sophisticated, more targeted, and harder to detect.

## The Problem Isn't New

We've known about dependency confusion since Alex Birsan's 2021 research. But somehow, teams still get hit by variants of the same attack. Why?

The answer is simple: **we're defending against yesterday's threat model**. Most security teams focus on known-malicious packages. Meanwhile, attackers have shifted to:

- Typosquatting with actual useful functionality (so reviews pass)
- Compromising maintainer accounts rather than publishing new packages
- Injecting malicious postinstall scripts that only trigger in CI environments

## What Actually Helps

After investigating several incidents, here's what I've seen actually reduce risk:

### 1. Pin Everything, Verify Everything

Lockfiles are table stakes, not a solution. You need to verify that what's in your lockfile matches what you expect. Tools like `npm audit signatures` are a start, but they only cover a fraction of the registry.

### 2. Monitor for Maintainer Changes

The most dangerous supply chain attacks come through legitimate packages with new maintainers. If `left-pad` suddenly has a new publisher, that's a signal worth investigating.

### 3. Reduce Your Attack Surface

Every dependency is a liability. Run `npx depcheck` regularly. You'd be surprised how many packages are imported but never used.

## The Uncomfortable Truth

There's no silver bullet. Supply chain security is a continuous process of reducing trust boundaries and increasing visibility. The teams that do it well treat their dependency graph like infrastructure — monitored, audited, and questioned regularly.

Your `node_modules` folder is part of your attack surface. Start treating it that way.
