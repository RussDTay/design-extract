import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ext = resolve(root, 'gemini/extract-design-corporate');
const read = (p) => readFileSync(p, 'utf-8');

test('gemini extension manifest is valid and in lockstep with package.json', () => {
  const m = JSON.parse(read(resolve(ext, 'gemini-extension.json')));
  const pkg = JSON.parse(read(resolve(root, 'package.json')));
  assert.equal(m.name, 'designlang-corporate');
  assert.equal(m.version, pkg.version);
});

test('gemini SKILL.md frontmatter has only name + single-line description', () => {
  const s = read(resolve(ext, 'skills/extract-design-corporate/SKILL.md'));
  const fm = s.match(/^---\n([\s\S]*?)\n---\n/);
  assert.ok(fm, 'frontmatter present at top of file');
  const lines = fm[1].split('\n');
  assert.equal(lines.length, 2, 'exactly two frontmatter lines');
  assert.match(lines[0], /^name: extract-design-corporate$/);
  assert.match(lines[1], /^description: \S/);
  assert.ok(!s.includes('CLAUDE_SKILL_DIR'), 'no Claude-only variables');
});

test('gemini wrapper script is identical to the Claude skill copy', () => {
  assert.equal(
    read(resolve(ext, 'skills/extract-design-corporate/scripts/designlang-safe.sh')),
    read(resolve(root, 'skills/extract-design-corporate/scripts/designlang-safe.sh')),
  );
});

test('gemini custom command defines a prompt', () => {
  const t = read(resolve(ext, 'commands/extract-design.toml'));
  assert.match(t, /^prompt = """/m);
  assert.match(t, /\{\{args\}\}/);
});
