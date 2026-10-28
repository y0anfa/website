---
title: Security should unleash
date: 2026-10-28
description: A security review that ships the feature is worth more than one that blocks it.
---

A team asks for a security review of a feature that stores customer files. The review comes back three weeks later with a list of concerns and no recommendation. The launch slips. Next time, the team asks for review later, or not at all.

The same review can go another way. The reviewer reads the design the day it arrives and asks what the team wants to ship, and by when. Then they say how to ship it: encrypt the files per customer and serve them through signed URLs. Two smaller risks stay open. They get written down, with an owner and a date. The feature ships on schedule.

Both reviews found the same problems. The second one treated the deadline as a requirement, like any other.

I try to judge my work by what shipped safely, not by what I stopped. A blocked launch costs the business something, and someone pays for it, usually through workarounds I never hear about. Security has to count that cost.

When someone brings me a plan, I ask what they need to ship. Then I ask for the smallest change that makes it safe.

Next time you review a design, end your comment with the change that lets it go out.
