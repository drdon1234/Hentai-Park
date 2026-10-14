// Keeps lib/ui on the design tokens (docs/DESIGN.md): colors come from the theme, radii from
// Radii, type sizes from TextTheme, and no weight heavier than 600. Token definitions live in
// lib/ui/theme.dart and lib/ui/kit/, which are exempt.
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ui = join(root, 'lib', 'ui');
const exempt = [join(ui, 'theme.dart'), join(ui, 'kit')];
const rules = [
  // Black, white and transparent stay allowed for image scrims and immersive readers.
  [/\bColors\.(?!black\b|white\b|transparent\b|black\d|white\d)\w+/g, 'use a ColorScheme role instead of a Material palette color'],
  [/\bColor\(0x[0-9a-fA-F]+\)/g, 'define colors in the theme or kit tokens'],
  [/\bBorderRadius\.circular\(/g, 'use Radii'],
  [/\bfontSize\s*:/g, 'use a TextTheme style'],
  [/\bFontWeight\.(w700|w800|w900|bold)\b/g, 'weights stop at w600'],
];

async function* dartFiles(folder) {
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    const path = join(folder, entry.name);
    if (exempt.some((e) => path === e || path.startsWith(e + '\\') || path.startsWith(e + '/'))) continue;
    if (entry.isDirectory()) yield* dartFiles(path);
    else if (entry.name.endsWith('.dart')) yield path;
  }
}

const failures = [];
for await (const path of dartFiles(ui)) {
  const lines = (await readFile(path, 'utf8')).split('\n');
  lines.forEach((line, i) => {
    if (/^\s*\/\//.test(line)) return;
    for (const [pattern, hint] of rules) {
      for (const match of line.matchAll(pattern)) {
        failures.push(`${relative(root, path)}:${i + 1}: ${match[0]} — ${hint}`);
      }
    }
  });
}
if (failures.length) {
  console.error(failures.join('\n'));
  console.error(`样式检查失败：${failures.length} 处未使用设计令牌`);
  process.exitCode = 1;
} else {
  console.log('样式检查通过：界面只使用主题与设计令牌。');
}
