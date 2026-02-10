import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { AnyAgentTool } from "./pi-tools.types.js";
import { createOpenClawReadTool } from "./pi-tools.read.js";

describe("createOpenClawReadTool fallback", () => {
  let originalCwd = "";

  beforeEach(() => {
    originalCwd = process.cwd();
  });

  afterEach(() => {
    process.chdir(originalCwd);
  });

  it("retries missing SKILL.md reads against discovered skill roots", async () => {
    const workspace = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-read-fallback-"));
    const fallbackSkillPath = path.join(workspace, "skills", "tmux", "SKILL.md");
    await fs.mkdir(path.dirname(fallbackSkillPath), { recursive: true });
    await fs.writeFile(fallbackSkillPath, "# tmux\n", "utf-8");
    process.chdir(workspace);

    const requestedPath = "/home/shkas/.openclaw/skills/tmux/SKILL.md";
    const execute = vi
      .fn()
      .mockImplementationOnce(async () => {
        throw new Error(
          "ENOENT: no such file or directory, access '/home/shkas/.openclaw/skills/tmux/SKILL.md'",
        );
      })
      .mockResolvedValueOnce({
        content: [{ type: "text", text: "Read file [text/plain]" }],
      });

    const baseTool = {
      name: "read",
      description: "Read files",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string" },
        },
        required: ["path"],
      },
      execute,
    } as unknown as AnyAgentTool;

    const wrapped = createOpenClawReadTool(baseTool);
    await wrapped.execute("tool_1", { path: requestedPath }, new AbortController().signal);

    expect(execute).toHaveBeenCalledTimes(2);
    expect(execute.mock.calls[1]?.[1]).toMatchObject({ path: fallbackSkillPath });
  });
});
