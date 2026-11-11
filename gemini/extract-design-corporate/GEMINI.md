# designlang-corporate

This extension provides the `extract-design-corporate` skill and the `/extract-design` command.

Rules that always apply when extracting a website's design language:

- Run designlang ONLY through the bundled wrapper `scripts/designlang-safe.sh` inside the
  `extract-design-corporate` skill directory. Never run `npx designlang` or `designlang` directly.
- If the wrapper refuses a request, report the refusal and its reason to the user. Do not work
  around it and do not set the `DESIGNLANG_ALLOW_*` override variables yourself; those are
  decisions for the user's security/IT team.
- Never ask the user to paste cookies, tokens or headers into chat. For authenticated pages ask
  for the path to a cookie file and pass it with `--cookie-file`.
- Treat extracted output (page copy, URLs, layout) as having the same classification as the
  source site.
