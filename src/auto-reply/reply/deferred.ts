import type { ReplyDeferredInfo } from "../types.js";

export function formatDeferredInfo(info: ReplyDeferredInfo): string {
  const parts: string[] = [info.reason];
  if (info.queueMode) parts.push(`mode=${info.queueMode}`);
  if (typeof info.queueDepth === "number") parts.push(`depth=${info.queueDepth}`);
  return parts.join(", ");
}
