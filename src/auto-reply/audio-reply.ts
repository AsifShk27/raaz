import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import type { ClawdbotConfig } from "../config/config.js";
import { logVerbose, shouldLogVerbose } from "../globals.js";
import { splitMediaFromOutput } from "../media/parse.js";
import { runExec } from "../process/exec.js";
import type { RuntimeEnv } from "../runtime.js";
import { applyTemplate, type TemplateContext } from "./templating.js";

type AudioReplyResult = {
  mediaUrls: string[];
  audioAsVoice?: boolean;
};

async function fileExists(candidate: string): Promise<boolean> {
  try {
    const stat = await fs.stat(candidate);
    return stat.isFile() && stat.size > 0;
  } catch {
    return false;
  }
}

export async function synthesizeReplyAudio(params: {
  cfg: ClawdbotConfig;
  ctx: TemplateContext;
  replyText: string;
  runtime: RuntimeEnv;
}): Promise<AudioReplyResult | undefined> {
  const { cfg, ctx, replyText, runtime } = params;
  const replyConfig = cfg.audio?.reply;
  if (!replyConfig?.command?.length) return undefined;

  const trimmedText = replyText.trim();
  if (!trimmedText) return undefined;

  const timeoutMs = Math.max((replyConfig.timeoutSeconds ?? 45) * 1000, 1_000);
  const id = crypto.randomUUID();
  const textPath = path.join(os.tmpdir(), `clawdbot-reply-${id}.txt`);
  const audioPath = path.join(os.tmpdir(), `clawdbot-reply-${id}.ogg`);

  try {
    await fs.writeFile(textPath, trimmedText, "utf8");
    const templateCtx: TemplateContext = {
      ...ctx,
      ReplyText: trimmedText,
      ReplyTextFile: textPath,
      ReplyAudioPath: audioPath,
    };
    const argv = replyConfig.command.map((part) =>
      applyTemplate(part, templateCtx),
    );
    if (!argv.length || !argv[0]) return undefined;
    if (shouldLogVerbose()) {
      logVerbose(`Synthesizing audio via command: ${argv.join(" ")}`);
    }
    const { stdout } = await runExec(argv[0], argv.slice(1), {
      timeoutMs,
      maxBuffer: 5 * 1024 * 1024,
    });
    const parsed = splitMediaFromOutput(stdout);
    let mediaUrls = parsed.mediaUrls;
    if (!mediaUrls?.length && (await fileExists(audioPath))) {
      mediaUrls = [audioPath];
    }
    if (!mediaUrls?.length) return undefined;
    return { mediaUrls, audioAsVoice: parsed.audioAsVoice };
  } catch (err) {
    runtime.error?.(`Audio reply failed: ${String(err)}`);
    return undefined;
  } finally {
    void fs.unlink(textPath).catch(() => {});
  }
}
