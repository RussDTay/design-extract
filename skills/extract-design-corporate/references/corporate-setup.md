# Corporate setup guide (for IT / platform / security teams)

This is for the people deploying the `extract-design-corporate` skill, not for end users.

## 1. Install a vetted copy (don't rely on `npx` at runtime)

```bash
# Review the package + its dependency tree, then publish/mirror it internally.
npm view designlang@13.4.0 dist.integrity
npm install --prefix /opt/designlang designlang@13.4.0 --ignore-scripts
export DESIGNLANG_BIN=/opt/designlang/node_modules/.bin/designlang
```

- Pin the version; bump deliberately after review (`CHANGELOG.md` is in the package).
- Point npm at your internal registry/Artifactory/Nexus (`npm config set registry …`).
- Run `npm audit` and your SCA scanner on the lockfile. Runtime dependencies are
  `playwright`, `commander`, `chalk`, `ora`, `pdf-lib`, `pixelmatch`, `pngjs`,
  `@modelcontextprotocol/sdk`. Requires Node >= 20.
- If you can't preinstall, leave `DESIGNLANG_BIN` unset and set `DESIGNLANG_VERSION`;
  the wrapper will use `npx designlang@<version>` with `npm_config_ignore_scripts=true`.

## 2. Browser

Chromium is not downloaded at install time. Options:

- **Managed Chrome (recommended):** `export DESIGNLANG_SYSTEM_CHROME=1`. No download, uses the
  OS certificate store and any system proxy configuration/PAC your device management provides.
- **Bundled Chromium from a mirror:** set `PLAYWRIGHT_DOWNLOAD_HOST=https://<internal-mirror>`
  and run `designlang install-browser` once at image-build time (not per user).

> The designlang CLI has no proxy flag of its own. If extraction fails behind a proxy, prefer
> system Chrome; if you still see connectivity problems, test with `designlang doctor` and
> verify with your network team that the target hosts are reachable from the browser process.
> (Not verified here: how every Playwright/Chromium version picks up proxy environment variables.)

## 3. Certificates

Never allow `--insecure`. For TLS inspection, install the corporate root CA into the OS trust
store and use system Chrome. For Node-side fetches add `NODE_EXTRA_CA_CERTS=/path/to/corp-root.pem`.

## 4. Policy environment variables

Put these in Claude Code **managed settings** (`env` block) so users can't loosen them:

```json
{
  "env": {
    "DESIGNLANG_BIN": "/opt/designlang/node_modules/.bin/designlang",
    "DESIGNLANG_ALLOWED_HOSTS": "example.com,staging.example.com",
    "DESIGNLANG_SYSTEM_CHROME": "1",
    "DESIGNLANG_AUDIT_LOG": "/var/log/designlang-audit.tsv"
  }
}
```

Leave `DESIGNLANG_ALLOW_SMART`, `DESIGNLANG_ALLOW_INSECURE` and `DESIGNLANG_ALLOW_INTERNAL` unset
unless a documented exception exists. `DESIGNLANG_ALLOW_INTERNAL=1` is needed for intranet,
staging on RFC1918 addresses, or `localhost` dev servers.

To make the wrapper tamper-resistant, install the skill via a managed plugin marketplace or
system-level skills directory rather than in user-writable project folders, and consider
adding `Bash(npx designlang:*)` and `Bash(designlang:*)` to your managed **deny** list so the
only path to the tool is the wrapper.

## 5. Data-handling facts worth knowing

| Item | Detail |
|---|---|
| Outbound requests | The browser visits the target URL and whatever it loads (CDNs, fonts, analytics). The target site will see the request (use `--user-agent` per your policy). |
| `designlang doctor` | Makes a reachability check to `api.github.com`; harmless if blocked (reports a warning). |
| `--smart` | Sends URL, title, ~1.5 KB of page text and class names to Anthropic/OpenAI/Atlas Cloud depending on which API key env var is present. Disabled by the wrapper. |
| Local history | Snapshots are written to `~/.designlang/` (up to 50 per host). Use `--no-history` for sensitive sites or include that directory in your retention policy. |
| Generated HTML | `*-preview.html`, clone and studio pages can link to `fonts.googleapis.com`. Block or accept this per your policy. |
| `studio` | Starts an HTTP server without an explicit bind address (all interfaces). Disabled by the wrapper. |
| Credit line | `--no-credit` removes the "Measured with designlang" attribution from generated files. |
| License | MIT. The tool extracts publicly rendered styles; that does not grant rights to a site's brand assets or content. |

## 6. CI usage (token drift gate)

```bash
bash skills/extract-design-corporate/scripts/designlang-safe.sh \
  drift https://www.example.com --tokens ./design-tokens.json --fail-on notable-drift --json
```

Exit status is non-zero when drift exceeds the threshold. Run it from a runner with the same
managed environment variables as above.

## 7. Smoke test after deployment

```bash
bash scripts/designlang-safe.sh doctor
bash scripts/designlang-safe.sh https://www.example.com -o /tmp/dl-test --no-history
bash scripts/designlang-safe.sh https://example.com --smart      # must be refused
bash scripts/designlang-safe.sh http://169.254.169.254/          # must be refused
```
