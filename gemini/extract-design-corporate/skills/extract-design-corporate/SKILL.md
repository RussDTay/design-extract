---
name: extract-design-corporate
description: Extract a website's design language (colors, typography, spacing, shadows, components, WCAG score) into design tokens, Tailwind/CSS/Figma/shadcn themes and a DESIGN.md under enterprise guardrails (pinned tool version, host allow-list, no inline credentials, no third-party LLM calls, audit log). Use in a corporate or regulated environment when the user asks to extract design, get design tokens from a URL, find what colors or fonts a site uses, audit brand consistency, or make a Tailwind theme from a site.
---

# Extract Design Language (corporate)

Runs `designlang` through a policy wrapper so extraction is safe on company machines.

**Locating the wrapper:** `<SKILL_DIR>` below means the directory that contains this SKILL.md
(its absolute path is where this skill was loaded from). The wrapper is
`<SKILL_DIR>/scripts/designlang-safe.sh`. **Never run `npx designlang` or `designlang`
directly. The wrapper is the only way to invoke the tool.**

## What the wrapper enforces

| Control | Behaviour |
|---|---|
| Version pinning | Uses `$DESIGNLANG_BIN` (vetted internal install) or `npx designlang@$DESIGNLANG_VERSION` with lifecycle scripts off. |
| Host policy | Honours `$DESIGNLANG_ALLOWED_HOSTS`; always blocks cloud-metadata/link-local addresses; blocks localhost/RFC1918 unless `$DESIGNLANG_ALLOW_INTERNAL=1`. |
| Credentials | Rejects inline `--cookie` / `--header`. Use `--cookie-file`. |
| Data egress | Rejects `--smart` (sends page text to an external LLM API) unless `$DESIGNLANG_ALLOW_SMART=1`. |
| TLS | Rejects `--insecure` unless `$DESIGNLANG_ALLOW_INSECURE=1`. |
| Listeners / unattended | Blocks `studio`, `mcp`, `watch`, `chat`. |
| Audit | Appends time, user, subcommand and host to `$DESIGNLANG_AUDIT_LOG` if set. |

If the wrapper refuses something, report the refusal and reason to the user. Do not work around
it: no direct `npx`, no editing the script, no setting the override variables yourself.

## Before you run anything

1. **Confirm authorization.** Only extract from sites the user owns, operates, or has a clear
   right to analyze. For a competitor or third-party site, warn that reproducing brand assets
   or a pixel clone may raise trademark/copyright issues and ask whether to proceed. Do not use
   `clone`, `pack --with-clone` or `fidelity` on third-party sites without that confirmation.
2. **Classify the target.** Output files include page copy, URLs and layout. Treat the output
   directory with the same classification as the source site.
3. **Authenticated pages:** ask for a path to a cookie/session file the user created
   (`--cookie-file`: Playwright storageState, JSON array or Netscape format). Never ask them to
   paste cookies or tokens into chat and never echo file contents.

## Process

1. Choose an output directory outside any git-tracked source tree unless the user wants tokens
   committed (e.g. `~/design-extract-output/<host>`), and pass it with `-o`.
2. Run:

```bash
bash <SKILL_DIR>/scripts/designlang-safe.sh <url> -o <out-dir>
```

   Useful additions: `--dark`, `--depth <n>`, `--wait <ms>`, `--screenshots`,
   `--framework react|shadcn|vue|svelte`, `--ignore-widgets`,
   `--platforms ios,android,flutter,wordpress`, `--no-history`, `--no-credit`.
3. Read `<out-dir>/*-design-language.md` and summarize: primary palette (hex), font families
   and scale, spacing base unit, WCAG accessibility score, component patterns, notable
   shadows/radii/motion.
4. Offer next steps (copy the Tailwind config, import the CSS variables, import Figma
   variables, open the preview). Apply changes to the user's project only after they confirm;
   `apply` and `sync` modify files in place.

Other subcommands available through the same wrapper: `diff <urlA> <urlB>`, `score <url>`,
`slop <url>`, `lint <tokens.json>`, `drift <url> --tokens <file>`, `history <url>`,
`stats <url...>`, `grade <url>`, `site <url>`.

## Outputs

| File | Purpose |
|---|---|
| `*-design-language.md` / `DESIGN.md` | AI-readable design system summary |
| `*-design-tokens.json` | W3C DTCG tokens |
| `*-tailwind.config.js`, `*-variables.css`, `*-theme.js`, `*-shadcn-theme.css` | Drop-in themes |
| `*-figma-variables.json` | Figma Variables import |
| `*-preview.html` | Visual report; may reference Google Fonts when opened online |

## Troubleshooting

- **"No browser available"**: Chromium isn't installed. Ask IT to preinstall it, or have them set
  `DESIGNLANG_SYSTEM_CHROME=1` to use the managed Chrome.
- **Certificate errors behind a TLS-inspecting proxy**: don't use `--insecure`; the browser must
  trust the corporate root CA (system Chrome uses the OS trust store).
- **Blocked by host policy**: ask the owner of `DESIGNLANG_ALLOWED_HOSTS` to add the host.
- **SSO/MFA or bot protection**: use a user-supplied `--cookie-file` from an authorized session;
  never try to bypass protections.
