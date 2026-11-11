---
name: extract-design-corporate
description: "Extract a website's design language (colors, typography, spacing, shadows, components, WCAG score) into design tokens, Tailwind/CSS/Figma/shadcn themes and a DESIGN.md — under enterprise guardrails: pinned tool version, host allow-listing, no inline credentials, no third-party LLM calls, no listeners, audit logging. Use in a corporate or regulated environment when the user says 'extract design', 'design tokens from our site', 'what colors/fonts does this site use', 'audit our brand consistency', 'make a Tailwind theme from this URL', or '/extract-design-corporate'. Prefer this over extract-design wherever company policy, internal sites or authenticated pages are involved."
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/designlang-safe.sh:*), Read, Glob
---

# Extract Design Language (corporate)

Runs `designlang` through a policy wrapper, `scripts/designlang-safe.sh`, so extraction is
safe to use on company machines. **Never call `npx designlang` or `designlang` directly in this
skill — always go through the wrapper.** It is the only command this skill is permitted to run.

## What the wrapper enforces

| Control | Behaviour |
|---|---|
| Version pinning | Uses `$DESIGNLANG_BIN` (vetted internal install) or `npx designlang@$DESIGNLANG_VERSION` with lifecycle scripts off. Never an unpinned `latest`. |
| Host policy | Honours `$DESIGNLANG_ALLOWED_HOSTS`; always blocks cloud-metadata/link-local addresses; blocks localhost/RFC1918 unless `$DESIGNLANG_ALLOW_INTERNAL=1`. |
| Credentials | Rejects inline `--cookie` / `--header` (they leak via process lists and shell history). Use `--cookie-file`. |
| Data egress | Rejects `--smart` (sends page text to an external LLM API) unless `$DESIGNLANG_ALLOW_SMART=1`. |
| TLS | Rejects `--insecure` unless `$DESIGNLANG_ALLOW_INSECURE=1`. Fix certificate errors with the corporate root CA instead. |
| Listeners / unattended | Blocks `studio`, `mcp`, `watch`, `chat`. |
| Audit | Appends time, user, subcommand and host (never cookies or URLs with queries) to `$DESIGNLANG_AUDIT_LOG` if set. |

If the wrapper refuses something, **report the refusal and its reason to the user. Do not try to
work around it** (no direct `npx`, no editing the script, no setting the override env vars yourself).
Overrides are a decision for the user's security/IT team, not for you.

## Before you run anything

1. **Confirm authorization.** Only extract from sites the user owns, operates, or has a clear
   right to analyze (company properties, partner sites under agreement, or public pages for
   ordinary internal reference). For a competitor or third-party site, tell the user that
   reproducing its brand assets or a pixel clone may raise trademark/copyright issues and ask
   whether to proceed. Do not use `clone`, `pack --with-clone` or `fidelity` on third-party sites
   without that confirmation.
2. **Classify the target.** Internal/staging/authenticated sites may contain confidential text.
   Output files include page copy (voice/tone, section text), URLs and layout. Treat the output
   directory with the same classification as the source site.
3. **Authenticated pages:** ask the user for a path to a cookie/session file they have created
   (`--cookie-file`, Playwright storageState, or Netscape format). Never ask them to paste
   cookies or tokens into chat, and never echo file contents. Remind them the file should be
   mode 600 and must not be committed.

## Process

1. Pick an output directory **outside any git-tracked source tree** unless the user wants the
   tokens committed (e.g. `~/design-extract-output/<host>`), and pass it with `-o`.
2. Run the extraction:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/designlang-safe.sh <url> -o <out-dir>
```

   Useful additions: `--dark` (dark scheme), `--depth <n>` (crawl n internal pages),
   `--wait <ms>` (slow SPAs), `--screenshots`, `--framework react|shadcn|vue|svelte`,
   `--ignore-widgets` (strip chat/cookie-banner widgets so they don't pollute tokens),
   `--platforms ios,android,flutter,wordpress`, `--no-history`, `--no-credit` (omit the
   "Measured with designlang" line from generated files — recommended for internal artifacts).
3. Read `<out-dir>/*-design-language.md` with the Read tool and summarize for the user:
   primary palette (hex), font families and scale, spacing base unit, WCAG accessibility
   score, component patterns, notable shadows/radii/motion.
4. Offer next steps (see "Outputs"). Only apply changes to the user's project after they
   confirm — `apply` and `sync` modify files in place.

Other read-mostly subcommands that run through the same wrapper:
`diff <urlA> <urlB>`, `score <url>`, `slop <url>`, `lint <tokens.json>`, `drift <url> --tokens <file>`,
`history <url>`, `stats <url…>`, `grade <url>`, `site <url>`. For `drift`/`verify` style checks
against a company design system, you can also run them as CI gates (see `references/corporate-setup.md`).

## Outputs

| File | Purpose |
|---|---|
| `*-design-language.md` / `DESIGN.md` | AI-readable design system summary |
| `*-design-tokens.json` | W3C DTCG tokens |
| `*-tailwind.config.js`, `*-variables.css`, `*-theme.js`, `*-shadcn-theme.css` | Drop-in themes |
| `*-figma-variables.json` | Figma Variables import |
| `*-preview.html` | Visual report. **Note:** it may reference Google Fonts; it will fall back to system fonts on air-gapped/blocked networks, and will make a request to Google if opened online. |

## Troubleshooting (corporate networks)

- **"No browser available"** — Chromium isn't installed. Ask IT to preinstall it or set
  `DESIGNLANG_SYSTEM_CHROME=1` to use the managed Chrome. See `references/corporate-setup.md`.
- **Certificate errors behind a TLS-inspecting proxy** — don't use `--insecure`. The browser
  must trust the corporate root CA (use system Chrome, which uses the OS trust store).
- **Blocked by host policy** — ask the owner of `DESIGNLANG_ALLOWED_HOSTS` to add the host.
- **Site blocks headless browsers or needs SSO/MFA** — use a user-supplied `--cookie-file`
  from an authorized session; don't attempt to bypass bot protection or MFA.
- **Handling the data afterwards** — extracted markdown/JSON is text you may now read into
  context. Don't paste secrets, tokens, or internal-only copy into external tools or tickets.
