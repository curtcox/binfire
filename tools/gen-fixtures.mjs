#!/usr/bin/env node
// Generates shared/fixtures/*.json, the conformance vectors that every port's
// unit tests consume. Run: node tools/gen-fixtures.mjs [--fk <path>] [--t256 <path>]
//
// Inputs (optional sibling checkouts; their data is copied into the fixtures so
// ports never need them):
//   --fk    Fragment Kit repo (tests/corpus/*.json)   default ../../Tools-for-pages-with-state-in-URL-fragments
//   --t256  256t.org repo (cids/ reference files)     default ../../256t.org
// If an input is missing, the previously generated data for it is kept.
import { loadCorpus } from './fixtures/context.mjs';
import genRegistry from './fixtures/registry.mjs';
import genCid from './fixtures/cid.mjs';
import genLz from './fixtures/lz.mjs';
import genEnvelope from './fixtures/envelope.mjs';
import genState from './fixtures/state.mjs';
import genLinks from './fixtures/links.mjs';
import genSiteManifest from './fixtures/site-manifest.mjs';
import genTransfer from './fixtures/transfer.mjs';
import genNearby from './fixtures/nearby.mjs';
import genQr from './fixtures/qr.mjs';
import genHashbin from './fixtures/hashbin.mjs';

// One module per fixture file in tools/fixtures/; shared setup is in tools/fixtures/context.mjs.
genRegistry();
genCid();
const corpus = loadCorpus();
genLz(corpus);
genEnvelope(corpus);
genState(corpus);
genLinks();
genTransfer(genSiteManifest());
genNearby();
genQr();
genHashbin();
