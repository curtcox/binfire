#!/usr/bin/env node
// Runs every check this machine can run and reports which platforms actually ran.
// Usage: node tools/check.mjs [shared|ios|android|flutter|rn ...]   (default: all)
import { spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const has = cmd => spawnSync('sh', ['-c', `command -v ${cmd}`]).status === 0;
const javaHome = () => spawnSync('sh', ['-c', '/usr/libexec/java_home -v 17 2>/dev/null']).stdout?.toString().trim();
const steps = {
  shared: [['tools', 'node configure.mjs --check'], ['tools', 'node --test test/*.test.mjs']],
  ios: has('swift') ? [['ios/BinfireCore', 'swift test']] : null,
  android: has('java') ? [['android', './gradlew --quiet :core:test :transfer:test']] : null,
  flutter: has('flutter') ? [['flutter', 'flutter test']] : null,
  rn: has('npm') ? [['react-native', 'npm test --silent'], ['react-native', 'npx tsc --noEmit']] : null,
};
const wanted = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(steps);
const results = [];
for (const name of wanted) {
  if (!steps[name]) { results.push([name, 'skipped (toolchain missing)']); continue; }
  let ok = true;
  for (const [dir, cmd] of steps[name]) {
    console.log(`\n=== ${name}: (cd ${dir} && ${cmd})`);
    const env = { ...process.env };
    const jh = name === 'android' && javaHome();
    if (jh) env.JAVA_HOME = jh;
    const r = spawnSync('sh', ['-c', cmd], { cwd: join(root, dir), stdio: 'inherit', env });
    if (r.status !== 0) { ok = false; break; }
  }
  results.push([name, ok ? 'passed' : 'FAILED']);
}
console.log('\nSummary:');
for (const [n, r] of results) console.log(`  ${n.padEnd(8)} ${r}`);
process.exit(results.some(([, r]) => r === 'FAILED') ? 1 : 0);
