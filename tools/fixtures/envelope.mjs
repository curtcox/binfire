// envelope.json: document type detection and the apps that accept each type.
// Called by tools/gen-fixtures.mjs.
import * as R from '../lib/ref.mjs';
import { registry, write, text } from './context.mjs';

export default function genEnvelope(corpus) {
  const appsFor = key => registry.apps.filter(a => a.documentTypes.includes(key)).map(a => a.slug);
  const envCases = [];
  for (const c of corpus) if (c.raw) envCases.push({ text: c.raw });
  envCases.push(
    { text: '"just a source string"' },
    { text: 'not json at all' },
    { text: '[1,2,3]' },
    { text: 'null' },
    { text: '{"format":"x-only"}' },
    { text: '{"format":1,"type":"python"}' },
    { text: '{"format":"hashbin-diagram","type":7}' },
    { text: '{"src":"bare"}' },
    { text: '{"format":"hashbin-diagram","version":1,"type":"nosuchapp","src":""}' },
    { b64: R.b64url(Buffer.from([0x7b, 0xff, 0x7d])) },
    { b64: R.b64url(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), text('{"format":"hashbin-diagram","type":"python"}')])), note: 'leading BOM is stripped' },
  );
  for (const e of envCases) {
    const bytes = e.text !== undefined ? text(e.text) : Buffer.from(e.b64, 'base64url');
    e.documentType = R.documentType(bytes);
    e.apps = e.documentType ? appsFor(e.documentType) : [];
  }
  write('envelope.json', { cases: envCases });
}
