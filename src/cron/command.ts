import { isRecord } from "../utils.js";
import type { CronCommandSpec } from "./types.js";

type UnknownRecord = Record<string, unknown>;

function normalizeArgv(raw: unknown): [string, ...string[]] | undefined {
  if (!Array.isArray(raw)) {
    return undefined;
  }
  const argv = raw
    .map((value) => (typeof value === "string" ? value.trim() : ""))
    .filter((value) => value.length > 0);
  if (argv.length === 0) {
    return undefined;
  }
  return argv as [string, ...string[]];
}

function normalizeEnv(raw: unknown): Record<string, string> | undefined {
  if (!isRecord(raw)) {
    return undefined;
  }
  const envEntries = Object.entries(raw)
    .map(([key, value]) => {
      const envKey = key.trim();
      if (!envKey || typeof value !== "string") {
        return null;
      }
      return [envKey, value] as const;
    })
    .filter((entry): entry is readonly [string, string] => entry !== null);
  if (envEntries.length === 0) {
    return undefined;
  }
  return Object.fromEntries(envEntries);
}

export function normalizeCronCommandSpec(raw: unknown): CronCommandSpec | undefined {
  if (!isRecord(raw)) {
    return undefined;
  }
  const record = raw as UnknownRecord;
  const argv = normalizeArgv(record.argv);
  if (!argv) {
    return undefined;
  }
  const cwd = typeof record.cwd === "string" ? record.cwd.trim() : "";
  const env = normalizeEnv(record.env);
  return {
    argv,
    cwd: cwd || undefined,
    env,
  };
}
