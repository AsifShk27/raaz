import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("heartbeat wake", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.resetModules();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("does not raise unhandledRejection when the handler throws", async () => {
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => {
      unhandled.push(reason);
    };
    process.on("unhandledRejection", onUnhandled);

    const { requestHeartbeatNow, setHeartbeatWakeHandler } = await import("./heartbeat-wake.js");
    const consoleSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    let calls = 0;
    setHeartbeatWakeHandler(async () => {
      calls += 1;
      if (calls === 1) {
        throw new Error("fetch failed");
      }
      return { status: "ran", durationMs: 1 };
    });

    requestHeartbeatNow({ reason: "test", coalesceMs: 1 });
    await vi.runOnlyPendingTimersAsync();
    await vi.runOnlyPendingTimersAsync();

    setHeartbeatWakeHandler(null);
    process.off("unhandledRejection", onUnhandled);
    consoleSpy.mockRestore();

    expect(calls).toBe(2);
    expect(unhandled).toHaveLength(0);
  });
});
