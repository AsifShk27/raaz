import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import type { OpenClawConfig } from "../config/config.js";
import { logVerbose, shouldLogVerbose } from "../globals.js";
import { resolvePreferredOpenClawTmpDir } from "../infra/tmp-openclaw-dir.js";
import { splitMediaFromOutput } from "../media/parse.js";
import { runExec } from "../process/exec.js";
import { defaultRuntime, type RuntimeEnv } from "../runtime.js";
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

/**
 * Synthesize voice audio from reply text using the configured audio.reply.command.
 *
 * The command receives template variables:
 * - {{ReplyText}} - the text to synthesize
 * - {{ReplyTextFile}} - path to a temp file containing the text
 * - {{ReplyAudioPath}} - suggested output path for the audio file
 *
 * The command should either:
 * - Print MEDIA:<path> to stdout
 * - Write audio to {{ReplyAudioPath}}
 *
 * @returns AudioReplyResult with mediaUrls, or undefined if synthesis failed/not configured
 */
export async function synthesizeReplyAudio(params: {
  cfg: OpenClawConfig;
  ctx: TemplateContext;
  replyText: string;
  runtime?: RuntimeEnv;
}): Promise<AudioReplyResult | undefined> {
  const { cfg, ctx, replyText } = params;
  const runtime = params.runtime ?? defaultRuntime;
  const replyConfig = cfg.audio?.reply;
  if (!replyConfig?.command?.length) {
    return undefined;
  }

  const trimmedText = replyText.trim();
  if (!trimmedText) {
    return undefined;
  }

  const timeoutMs = Math.max((replyConfig.timeoutSeconds ?? 45) * 1000, 1_000);
  const id = crypto.randomUUID();
  // Keep synthesized media under OpenClaw's trusted temp root so media send-path
  // allowlists work consistently for both service and foreground runs.
  const tmpRoot = resolvePreferredOpenClawTmpDir();
  const textPath = path.join(tmpRoot, `openclaw-reply-${id}.txt`);
  const audioPath = path.join(tmpRoot, `openclaw-reply-${id}.ogg`);

  try {
    await fs.writeFile(textPath, trimmedText, "utf8");
    const templateCtx: TemplateContext = {
      ...ctx,
      ReplyText: trimmedText,
      ReplyTextFile: textPath,
      ReplyAudioPath: audioPath,
    };
    const argv = replyConfig.command.map((part) => applyTemplate(part, templateCtx));
    if (!argv.length || !argv[0]) {
      return undefined;
    }
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
    if (!mediaUrls?.length) {
      return undefined;
    }
    return { mediaUrls, audioAsVoice: parsed.audioAsVoice };
  } catch (err) {
    runtime.error?.(`Audio reply failed: ${String(err)}`);
    return undefined;
  } finally {
    void fs.unlink(textPath).catch(() => {});
  }
}
