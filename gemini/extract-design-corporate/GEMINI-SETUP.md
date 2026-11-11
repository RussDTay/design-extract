# Running `extract-design-corporate` in Gemini CLI

Everything needed to run the corporate-safe designlang skill under Gemini CLI: what was
ported, how to install it, how admins lock it down, and how to test that the guardrails hold.

> **Verification status.** Items marked **[verify]** come from search-result summaries of the
> Gemini CLI docs, or are not confirmed at all, because the doc pages could not be fetched
> while this was written. Check them against the docs for the Gemini CLI version you deploy
> (see [Sources](#sources)).

---

## 1. What is in this folder

```
gemini/extract-design-corporate/
├── gemini-extension.json                      # extension manifest (version tracks package.json)
├── GEMINI.md                                  # always-on context: the 4 non-negotiable rules
├── GEMINI-SETUP.md                            # this file
├── commands/extract-design.toml               # /extract-design slash command
└── skills/extract-design-corporate/
    ├── SKILL.md                               # Gemini-format skill (name + description only)
    └── scripts/designlang-safe.sh             # the policy wrapper (identical to the Claude copy)
```

`tests/gemini-extension.test.js` fails CI if the manifest version drifts, if the SKILL.md
frontmatter gains fields, or if the wrapper copy diverges from
`skills/extract-design-corporate/scripts/designlang-safe.sh`. When you change one copy, copy it
to the other.

## 2. What changed versus the Claude Code version

| Claude Code skill | Gemini version | Why |
|---|---|---|
| Frontmatter has `name`, `description`, `allowed-tools` | Only `name` and `description`, description on one line | Gemini docs say not to add other frontmatter fields **[verify]**; `allowed-tools` has no Gemini equivalent. |
| `allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/designlang-safe.sh:*)` restricts the shell to the wrapper | Same restriction moved into **Gemini policy rules** (section 5) | In Gemini, tool restriction is enforced by the policy engine, not by the skill. |
| `${CLAUDE_SKILL_DIR}` | `<SKILL_DIR>` = directory containing SKILL.md | Claude-only variable. Gemini injects the skill and its bundled assets on activation; scripts are referenced relative to the skill folder **[verify]**. |
| `.claude-plugin/` + `commands/*.md` | `gemini-extension.json` + `commands/*.toml` | Gemini extension and custom-command formats. |
| Claude managed settings `env` block | System-level environment (shell profile, container env, or MDM) | Gemini settings are not documented to inject env vars for shell tools. The wrapper reads plain environment variables, so set them where the Gemini process starts. |
| `references/corporate-setup.md` | Section 6 below | Admin material is merged into this file. |

The wrapper itself is plain bash and works unchanged. Needs: bash, Node >= 20, and either
`DESIGNLANG_BIN` or `npx`. Windows users need WSL or Git Bash.

## 3. Install

Pick one. All three assume Gemini CLI is already installed and authenticated.

**A. Extension, local development / pilot**

```bash
gemini extensions link ./gemini/extract-design-corporate      # [verify command name]
```

**B. Extension, from your internal git host**

```bash
gemini extensions install https://git.example.corp/platform/designlang-gemini.git   # [verify]
```

Gemini installs from a repo root. Either publish `gemini/extract-design-corporate/` as its own
repository, or confirm your CLI version supports a subdirectory.

**C. Plain skill, no extension (simplest and most predictable)**

```bash
# per user
mkdir -p ~/.gemini/skills && cp -R gemini/extract-design-corporate/skills/extract-design-corporate ~/.gemini/skills/
# per project (commit it)
mkdir -p .gemini/skills && cp -R gemini/extract-design-corporate/skills/extract-design-corporate .gemini/skills/
```

`~/.agents/skills/` and `.agents/skills/` are documented aliases, and `.agents` wins if both
exist **[verify]**. SKILL.md must sit exactly one level inside the skills folder, and its
filename is case-sensitive. A skill missing `name` or `description` is silently skipped.

Option C does not install the `/extract-design` command or `GEMINI.md`. If you want those, copy
`commands/extract-design.toml` to `~/.gemini/commands/` (or `.gemini/commands/`) and append the
contents of `GEMINI.md` to your project's `GEMINI.md`.

**Enable / verify skills are on.** Some versions treated skills as experimental. I could not
confirm a flag **[verify]**. In an interactive session run `/skills` (or `gemini skills list`
**[verify]**) and check that `extract-design-corporate` appears.

## 4. Runtime environment (set where Gemini starts)

| Variable | Purpose | Recommended |
|---|---|---|
| `DESIGNLANG_BIN` | Absolute path to a vetted, preinstalled `designlang` | set |
| `DESIGNLANG_VERSION` | Pinned version for the `npx` fallback (wrapper default `13.4.0`) | set if no `DESIGNLANG_BIN` |
| `DESIGNLANG_ALLOWED_HOSTS` | Comma-separated host suffixes the tool may visit | set |
| `DESIGNLANG_SYSTEM_CHROME` | `1` = use managed Chrome, skip Chromium download | `1` |
| `DESIGNLANG_AUDIT_LOG` | File receiving one TSV line per run (time, user, subcommand, host) | set |
| `DESIGNLANG_ALLOW_INTERNAL` | `1` permits localhost / RFC1918 targets | unset unless needed |
| `DESIGNLANG_ALLOW_SMART` | `1` permits `--smart` (page text to a third-party LLM API) | **unset** |
| `DESIGNLANG_ALLOW_INSECURE` | `1` permits `--insecure` (no TLS verification) | **unset** |

Gemini's shell tool may filter or sanitize the child-process environment **[verify]**. After
setup, confirm with the smoke test in section 8 that the wrapper actually sees these values (for
example, that the `DESIGNLANG_ALLOWED_HOSTS` refusal fires).

## 5. Enforce "wrapper only" with Gemini policy rules

Claude's `allowed-tools` line is the control that keeps the model from calling `npx designlang`
directly. In Gemini the equivalent is a TOML policy. Policies are evaluated highest priority
first and the first match decides **[verify]**; decisions are `allow`, `deny` or `ask_user`;
`commandPrefix` and `commandRegex` cannot appear in the same rule.

Save as `designlang-corporate.toml` in your admin policy directory:

```toml
# Block direct invocation of the tool; the wrapper is the only path.
[[rule]]
toolName = "run_shell_command"
commandPrefix = "npx designlang"
decision = "deny"
priority = 900
denyMessage = "Run designlang only through designlang-safe.sh (corporate policy)."

[[rule]]
toolName = "run_shell_command"
commandPrefix = "designlang"
decision = "deny"
priority = 900
denyMessage = "Run designlang only through designlang-safe.sh (corporate policy)."

# Block the wrapper-bypass override variables from being set in-session.
[[rule]]
toolName = "run_shell_command"
commandRegex = ".*DESIGNLANG_ALLOW_[A-Z]+=.*"
decision = "deny"
priority = 900
denyMessage = "Policy overrides must be set by IT, not in-session."

# Allow the wrapper, still asking the user each time.
[[rule]]
toolName = "run_shell_command"
commandPrefix = "bash "          # tighten to your absolute install path, e.g. "bash /opt/designlang-skill/scripts/designlang-safe.sh"
decision = "ask_user"
priority = 800
```

Notes:

- **Where it goes:** the Admin tier is OS-specific and I could not confirm the exact Linux
  path **[verify]**. The documented route is the `adminPolicyPaths` setting in the system
  `settings.json`. Supplemental admin policies are ignored if `.toml` files already exist in the
  standard system policy location. Admin rules outrank User, Workspace and Default rules, but the
  tier-priority numbering is inconsistent across docs (4.x vs 5.x), so keep all rules in one
  tier and use explicit priorities as above.
- **Shell-chaining:** confirm how your version matches prefixes against chained commands
  (`a && npx designlang ...`, subshells, `env X=1 npx designlang`). Deny rules for the
  chained and `env`-prefixed forms may be needed **[verify]**. Test it (section 8).
- **Hard lock-down alternative:** install the wrapper at a root-owned path
  (`/opt/designlang-skill/scripts/designlang-safe.sh`, mode 755) and make the `ask_user`
  rule's prefix that exact absolute path, so a user-writable copy of the script can't be
  substituted.
- **Project-level policy:** workspace-tier policies were reported as not yet functional
  **[verify]**; don't rely on them for enforcement.

## 6. Admin hardening checklist

### 6.1 Vetted tool install

```bash
npm view designlang@13.4.0 dist.integrity
npm install --prefix /opt/designlang designlang@13.4.0 --ignore-scripts
export DESIGNLANG_BIN=/opt/designlang/node_modules/.bin/designlang
```

Pin the version, point npm at your internal registry, and run SCA over the lockfile. Runtime
dependencies: `playwright`, `commander`, `chalk`, `ora`, `pdf-lib`, `pixelmatch`, `pngjs`,
`@modelcontextprotocol/sdk`. Requires Node >= 20.

### 6.2 Browser

Chromium is not downloaded at install time. Either set `DESIGNLANG_SYSTEM_CHROME=1` (managed
Chrome, OS certificate store) or mirror Chromium with `PLAYWRIGHT_DOWNLOAD_HOST=https://<mirror>`
and run `designlang install-browser` at image-build time. designlang has no proxy flag; if
extraction fails behind a proxy, prefer system Chrome and test with `designlang doctor`.

### 6.3 Certificates

Never allow `--insecure`. Install the corporate root CA in the OS trust store and use system
Chrome. For Node-side fetches add `NODE_EXTRA_CA_CERTS=/path/to/corp-root.pem`.

### 6.4 Gemini CLI system settings

Put a system settings file at `/etc/gemini-cli/settings.json` (Linux; other OSes differ, or set
`GEMINI_CLI_SYSTEM_SETTINGS_PATH`). System settings override user and workspace settings
**[verify]**. Candidate settings, with the key names to check against your version:

```json
{
  "security": { "disableYoloMode": true },
  "tools": { "sandbox": "docker" },
  "privacy": { "usageStatisticsEnabled": false },
  "telemetry": { "enabled": true, "logPrompts": false },
  "mcp": { "allowed": [] }
}
```

- `security.disableYoloMode`: stops users from auto-approving every tool call, which would
  bypass `ask_user` rules.
- `tools.sandbox`: runs tool execution in a container. If you sandbox, the wrapper, Node,
  Chrome and the env vars must exist inside the sandbox image.
- `mcp.allowed`: without an allow-list users can add their own MCP servers. Avoid underscores in
  MCP server aliases; reports say they can break policy matching **[verify]**.
- Authentication: enforce your approved auth type (key name differs by release:
  `enforcedAuthType` vs `security.auth.enforcedType`) **[verify]**.
- Do not use the deprecated `tools.exclude`/`excludeTools` for this; use policy rules.

### 6.5 Data handling, Gemini-specific

This is the biggest difference from the Claude version. Whatever Gemini **reads** is sent to
its model provider. That includes extracted markdown and JSON from the target site, so:

- Use the Gemini auth path your company has approved (for example Vertex AI or an enterprise
  tier with contractual data terms), and enforce it via the setting in 6.4.
- Classify the extraction output like the source site. For confidential or internal sites, do not
  have the model read the generated `*-design-language.md`; have the user open the files locally.
- `designlang --smart` calls Anthropic, OpenAI or Atlas Cloud (not Gemini) based on which key is
  in the environment. The wrapper blocks it. Leave those API keys out of the environment.
- designlang writes snapshots to `~/.designlang/` (up to 50 per host). Use `--no-history` for
  sensitive sites or include the folder in your retention policy.
- `*-preview.html` may link to `fonts.googleapis.com` when opened online.

## 7. Using it

- Natural language: "extract the design tokens from https://www.example.com". The skill's
  description should trigger `activate_skill`, and the user is asked to consent **[verify]**.
- Slash command: `/extract-design https://www.example.com --dark -o ~/design-out`.
- The first action should be the authorization check from SKILL.md; the model then runs
  `bash <SKILL_DIR>/scripts/designlang-safe.sh <url> -o <dir>`.

## 8. Smoke test after deployment

Run these inside Gemini (or directly with `bash`), and confirm each expected result:

| Action | Expected |
|---|---|
| `bash <SKILL_DIR>/scripts/designlang-safe.sh doctor` | Runs; Chromium/Chrome check reported |
| Wrapper with `https://www.example.com -o /tmp/dl-test --no-history` | Produces `/tmp/dl-test/*-design-language.md` |
| Wrapper with `https://example.com --smart` | Refused (exit 2) |
| Wrapper with `https://example.com --insecure` | Refused |
| Wrapper with `https://example.com --cookie a=b` | Refused |
| Wrapper with `http://169.254.169.254/` | Refused (metadata endpoint) |
| Wrapper with `http://localhost:3000` | Refused unless `DESIGNLANG_ALLOW_INTERNAL=1` |
| Wrapper with a host outside `DESIGNLANG_ALLOWED_HOSTS` | Refused |
| Wrapper with `studio` | Refused |
| Ask Gemini to run `npx designlang https://example.com` | Denied by policy (section 5) |
| Ask Gemini to run `env DESIGNLANG_ALLOW_SMART=1 bash ...designlang-safe.sh ...` | Denied by policy |
| Check `$DESIGNLANG_AUDIT_LOG` | One new line per successful run, with host only |

If a policy-denied command still executes, the rule did not match your version's prefix logic.
Fix the rule before rolling out.

## 9. Known limitations

- The wrapper and policy rules reduce risk; they are not a sandbox. A user with shell access can
  run designlang directly outside Gemini. Pair this with the sandbox, managed install paths and
  endpoint controls.
- No Gemini equivalent of per-skill `allowed-tools`; enforcement lives only in policy rules.
- Skill discovery, path handling and the extension install command vary across Gemini CLI
  releases. Re-run the smoke test after each upgrade.
- The extension duplicates the wrapper script; the test suite guards the two copies.

## Sources

- [Creating Agent Skills](https://geminicli.com/docs/cli/creating-skills/)
- [Get started with Agent Skills](https://geminicli.com/docs/cli/tutorials/skills-getting-started/)
- [Build Gemini CLI extensions](https://geminicli.com/docs/extensions/writing-extensions/)
- [Extension reference](https://geminicli.com/docs/extensions/reference/)
- [Policy engine](https://geminicli.com/docs/reference/policy-engine/)
- [Gemini CLI for the enterprise](https://geminicli.com/docs/cli/enterprise/)
- [Gemini CLI configuration reference](https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/configuration.md)
