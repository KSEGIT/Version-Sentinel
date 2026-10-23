import { HtmlValidate } from 'html-validate';
import { readdir, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const validator = new HtmlValidate();
const files = (await readdir('public', { recursive: true })).filter(file => file.endsWith('.html'));
let failures = 0;
const reports = [];
for (const file of files) {
  const report = await validator.validateFile(path.join('public', file));
  reports.push({ file, ...report });
  failures += report.errorCount + report.warningCount;
  for (const result of report.results) for (const message of result.messages) console.error(`${file}:${message.line}:${message.column} ${message.ruleId}: ${message.message}`);
}
await mkdir('reports/html', { recursive: true });
await writeFile('reports/html/results.json', JSON.stringify(reports, null, 2));
console.log(`Validated ${files.length} HTML documents; ${failures} failures`);
if (failures) process.exitCode = 1;
