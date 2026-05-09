import { describe, expect, it, vi } from "vitest";
import { createMockCronStateForJobs } from "./service.test-harness.js";
import { executeJobCoreWithTimeout } from "./service/timer.js";
import type { CronJob } from "./types.js";

function makeCommandJob(argv: [string, ...string[]]): CronJob {
  const now = Date.now();
  return {
    id: "job-command",
    name: "deterministic-command",
    enabled: true,
    createdAtMs: now,
    updatedAtMs: now,
    schedule: { kind: "at", at: new Date(now + 60_000).toISOString() },
    sessionTarget: "isolated",
    wakeMode: "now",
    payload: {
      kind: "agentTurn",
      message: "run deterministic command",
      timeoutSeconds: 5,
      command: { argv },
    },
    delivery: { mode: "none" },
    state: {},
  };
}

describe("cron deterministic command payload", () => {
  it("runs command payload without isolated model execution", async () => {
    const job = makeCommandJob([process.execPath, "-e", "console.log('cron-command-ok')"]);
    const runIsolatedAgentJob = vi.fn(async () => ({ status: "ok" as const }));
    const state = createMockCronStateForJobs({ jobs: [job] });
    state.deps.runIsolatedAgentJob = runIsolatedAgentJob as never;

    const result = await executeJobCoreWithTimeout(state, job);

    expect(result.status).toBe("ok");
    expect(result.summary).toContain("cron-command-ok");
    expect(runIsolatedAgentJob).not.toHaveBeenCalled();
  });

  it("returns execution error details for non-zero command exits", async () => {
    const job = makeCommandJob([
      process.execPath,
      "-e",
      "console.error('cron-command-failed'); process.exit(3);",
    ]);
    const runIsolatedAgentJob = vi.fn(async () => ({ status: "ok" as const }));
    const state = createMockCronStateForJobs({ jobs: [job] });
    state.deps.runIsolatedAgentJob = runIsolatedAgentJob as never;

    const result = await executeJobCoreWithTimeout(state, job);

    expect(result.status).toBe("error");
    expect(result.error).toContain("exit code 3");
    expect(result.error).toContain("cron-command-failed");
    expect(runIsolatedAgentJob).not.toHaveBeenCalled();
  });
});
