# AGENTS.md — org-islam

One package that makes Org mode work with Islamic (Hijri) dates the
way it works with Gregorian ones, and extends Emacs' built-in
`cal-islam.el` into a complete Islamic calendar (maghrib day
boundary, Arabic timestamp overlays).  Plain Elisp, Emacs 27.1+,
Org 9.4+.

## Laws

- GPL-3.0-or-later; keep headers and SPDX tags.
- Pure Elisp: no external binaries, no network at runtime, no
  patching of Org or `cal-islam.el` themselves — everything hooks
  in via public APIs (font-lock keywords, advice, defcustoms).
- One package, deliberately: no org-awqat/org-hijri split (Owner
  order 2026-11-23).  Awqat is a soft dependency used only for
  maghrib times when installed.
- Storage convention is HARD LAW: Hijri timestamps live in Org
  files as ordinary Gregorian Org timestamps tagged "Hijri" in the
  day-name slot.  Only Hijri-marked timestamps display as Hijri;
  Gregorian timestamps are never touched.
- The maghrib day boundary comes from Awqat when available, else
  `solar.el`, else the fixed fallback — never invent times.
- `make compile` treats warnings as errors; `make test` is offline
  ERT (maghrib source pinned to `fixed` where a time matters).
- Do not quote user prompts in commits, docs or releases; describe
  the change, not the conversation.
- Commits: authored as the model identity `MODEL <model@provider>`
  (e.g. `GLM 5.3 <glm-5.3@z.ai>`), ending with BOTH trailers:

        Co-authored-by: Z.ai agent <agent@chat.z.ai>
        Co-authored-by: Khalid Rafi <khaalidrafi@gmail.com>

  Canonical owner email is `khaalidrafi@gmail.com` — no variants
  (Owner order 2026-11-24).
- Never commit directly to `main`.  Branch `ai/main` is the working
  default; feature work on `ai/<topic>`.
- Pushes use the Khalid's Slave GitHub App credential helper (never
  a stored PAT, never the plugin).
