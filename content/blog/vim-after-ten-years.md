---
title: "Vim After Ten Years: What Stayed, What Changed"
date: 2026-01-20
tags: ["dev", "tools"]
subtitle: "A love letter to muscle memory."
---

I started using Vim in university because someone told me it would make me a better programmer. That was wrong — Vim doesn't make you better at programming any more than a good pen makes you a better writer. But it did change my relationship with text in ways I didn't expect.

## What Stayed

The core keybindings. `ciw`, `dd`, `/%pattern`, `:s` — these are in my fingers now, not my head. I don't think about them any more than I think about how to type the letter 'e'. That's the real value of Vim: not speed, but *absence of friction*.

The philosophy of composability. Verbs + nouns + modifiers. `d2w` (delete two words), `ci"` (change inside quotes), `>ap` (indent a paragraph). Once you internalize the grammar, you can construct commands you've never used before and they just work.

## What Changed

**I stopped caring about plugins.** My `.vimrc` used to be 400 lines of carefully tuned configuration. Now it's about 40. The defaults are fine. The fewer plugins you have, the fewer things break when you update.

**I use Neovim now.** The async support and Lua configuration won. I resisted for years out of loyalty, which in retrospect was silly.

**I stopped evangelizing.** Use whatever editor makes you productive. The editor wars are boring and the answer is always "it depends." If VS Code with Vim keybindings works for you, that's great. The tool matters less than the craft.

## The One Thing I'd Tell Past Me

Learn the built-in features before reaching for plugins. `:grep`, `:make`, quickfix lists, macros, registers — Vim ships with incredibly powerful features that most people never discover because they install a plugin first.
