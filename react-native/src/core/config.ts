import { config as sharedConfig, registry as sharedRegistry } from '../generated/shared';

/** Bounds from `config/binfire.config.json` `limits`. */
export interface Limits {
  maxStateBytes: number;
  maxSiteFileBytes: number;
  maxSiteTotalBytes: number;
  maxSiteFiles: number;
  maxTransferBytes: number;
}

/** The subset of `config/binfire.config.json` that core logic uses. */
export interface BinfireConfig {
  appName: string;
  linkDomain: string;
  scheme: string;
  /** This port's private reverse-DNS scheme (its app ID); route() treats it like `scheme`. */
  ownScheme: string;
  /** `maxCostCents` is always sent as `max_cost_cents` (spec/hashbin.md "Cost"). */
  hashbin: { api: string; content: string; clientId: string; maxCostCents: number };
  ble: { serviceUuid: string; controlCharacteristicUuid: string; dataCharacteristicUuid: string };
  limits: Limits;
  oauthRedirect: string;
}

/** One app in `shared/registry/apps.json` (spec/registry.md). */
export interface RegistryApp {
  slug: string;
  name: string;
  canonicalOrigin: string;
  recoveryOrigin: string;
  otherOrigins: readonly string[];
  documentTypes: readonly string[];
  offlineManifest: string | null;
  icon: string | null;
  capabilities: Readonly<Record<string, unknown>>;
}

export interface Registry {
  format: string;
  version: number;
  apps: readonly RegistryApp[];
}

/** Everything injectable that core functions depend on. */
export interface BinfireContext {
  config: BinfireConfig;
  registry: Registry;
}

/** The config written by tools/configure.mjs. */
export const defaultConfig: BinfireConfig = sharedConfig;

/** The registry written by tools/configure.mjs. */
export const defaultRegistry: Registry = sharedRegistry;

export const defaultContext: BinfireContext = { config: defaultConfig, registry: defaultRegistry };
