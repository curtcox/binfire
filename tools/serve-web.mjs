#!/usr/bin/env node
// Serves shared/web locally the way production hosting should: real files when
// they exist, index.html otherwise. Usage: node tools/serve-web.mjs [port]
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, normalize, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const web = join(dirname(fileURLToPath(import.meta.url)), '..', 'shared', 'web');
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json' };
const port = Number(process.argv[2] ?? 8080);
createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
  let file = join(web, path), body;
  try { body = await readFile(file); } catch { file = join(web, 'index.html'); body = await readFile(file); }
  const type = file.includes('.well-known') ? 'application/json' : types[extname(file)] ?? 'application/octet-stream';
  res.writeHead(200, { 'content-type': type }).end(body);
}).listen(port, () => console.log(`binfire.app preview on http://localhost:${port}/`));
