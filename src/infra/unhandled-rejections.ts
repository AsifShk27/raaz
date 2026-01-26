import process from "node:process";

import { extractErrorCode, formatUncaughtError } from "./errors.js";

type UnhandledRejectionHandler = (reason: unknown) => boolean;

const handlers = new Set<UnhandledRejectionHandler>();

function extractCauseCode(reason: unknown): string | undefined {
  if (!reason || typeof reason !== "object") return undefined;
  const cause = (reason as { cause?: unknown }).cause;
  if (!cause || typeof cause !== "object") return undefined;
  return extractErrorCode(cause);
}

function isFetchAbortOrNetworkFailure(reason: unknown): boolean {
  if (!(reason instanceof Error)) return false;

  const name = reason.name?.toLowerCase() ?? "";
  if (name === "aborterror") return true;

  const message = (reason.message ?? "").toLowerCase();
  if (message.includes("fetch failed")) return true;

  const code = (extractErrorCode(reason) ?? extractCauseCode(reason) ?? "").toUpperCase();
  if (!code) return false;

  const networkCodes = new Set([
    "ECONNREFUSED",
    "ECONNRESET",
    "EHOSTUNREACH",
    "ENETUNREACH",
    "ENOTFOUND",
    "ETIMEDOUT",
    "UND_ERR_ABORTED",
    "UND_ERR_CONNECT_TIMEOUT",
    "UND_ERR_HEADERS_TIMEOUT",
    "UND_ERR_SOCKET",
  ]);
  return networkCodes.has(code);
}

export function registerUnhandledRejectionHandler(handler: UnhandledRejectionHandler): () => void {
  handlers.add(handler);
  return () => {
    handlers.delete(handler);
  };
}

export function isUnhandledRejectionHandled(reason: unknown): boolean {
  for (const handler of handlers) {
    try {
      if (handler(reason)) return true;
    } catch (err) {
      console.error(
        "[clawdbot] Unhandled rejection handler failed:",
        err instanceof Error ? (err.stack ?? err.message) : err,
      );
    }
  }
  return false;
}

export function installUnhandledRejectionHandler(): void {
  process.on("unhandledRejection", (reason, _promise) => {
    if (isUnhandledRejectionHandled(reason)) return;
    if (isFetchAbortOrNetworkFailure(reason)) {
      console.warn(
        "[clawdbot] Unhandled fetch/network rejection (ignored):",
        formatUncaughtError(reason),
      );
      return;
    }
    console.error("[clawdbot] Unhandled promise rejection:", formatUncaughtError(reason));
    process.exit(1);
  });
}
