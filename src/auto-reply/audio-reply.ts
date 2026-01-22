// Voice reply synthesis module - converts text replies to audio using configured command

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

/**
 * Check if a media type represents audio.
 * @param mediaType - MIME type string (e.g., "audio/ogg", "audio/mpeg")
 * @returns true if the media type is audio
 */
export function isAudio(mediaType?: string | null): boolean {
  if (!mediaType) return false;
  return mediaType.toLowerCase().startsWith("audio/");
}

/**
 * Synthesize voice audio from reply text using the configured audio.reply settings.
 *
 * Supports multiple providers:
 * - "command": External CLI tool (Piper, Pocket TTS, sherpa-onnx-tts, etc.)
 * - "elevenlabs": ElevenLabs API directly
 * - "sag": sag CLI wrapper for ElevenLabs
 *
 * For "command" provider, template variables are supported:
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
  cfg: ClawdbotConfig;
  ctx: TemplateContext;
  replyText: string;
  runtime: RuntimeEnv;
}): Promise<AudioReplyResult | undefined> {
  const { cfg, ctx, replyText, runtime } = params;
  const replyConfig = cfg.audio?.reply;

  // Check if reply synthesis is enabled
  if (!replyConfig?.enabled && replyConfig?.enabled !== undefined) {
    return undefined;
  }

  // Check for triggerOnVoice - only trigger when inbound was voice
  if (replyConfig?.triggerOnVoice && !isAudio(ctx.MediaType)) {
    return undefined;
  }

  const provider = replyConfig?.provider ?? "command";
  const trimmedText = replyText.trim();
  if (!trimmedText) return undefined;

  const timeoutMs = Math.max((replyConfig?.timeoutSeconds ?? 45) * 1000, 1_000);

  switch (provider) {
    case "command":
      return synthesizeViaCommand({ cfg, ctx, trimmedText, timeoutMs, runtime });
    case "elevenlabs":
      return synthesizeViaElevenLabs({ cfg, trimmedText, timeoutMs, runtime });
    case "sag":
      return synthesizeViaSag({ cfg, trimmedText, timeoutMs, runtime });
    default:
      runtime.error?.(`Unknown TTS provider: ${provider}`);
      return undefined;
  }
}

/**
 * Synthesize audio using a custom command (Piper, Pocket TTS, etc.)
 */
async function synthesizeViaCommand(params: {
  cfg: ClawdbotConfig;
  ctx: TemplateContext;
  trimmedText: string;
  timeoutMs: number;
  runtime: RuntimeEnv;
}): Promise<AudioReplyResult | undefined> {
  const { cfg, ctx, trimmedText, timeoutMs, runtime } = params;
  const replyConfig = cfg.audio?.reply;

  if (!replyConfig?.command?.length) {
    return undefined;
  }

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
    const argv = replyConfig.command.map((part: string) =>
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
    return { mediaUrls, audioAsVoice: parsed.audioAsVoice ?? true };
  } catch (err) {
    runtime.error?.(`Audio reply (command) failed: ${String(err)}`);
    return undefined;
  } finally {
    void fs.unlink(textPath).catch(() => {});
  }
}

/**
 * Synthesize audio using ElevenLabs API directly
 */
async function synthesizeViaElevenLabs(params: {
  cfg: ClawdbotConfig;
  trimmedText: string;
  timeoutMs: number;
  runtime: RuntimeEnv;
}): Promise<AudioReplyResult | undefined> {
  const { cfg, trimmedText, timeoutMs, runtime } = params;
  const replyConfig = cfg.audio?.reply;
  const elevenLabsConfig = replyConfig?.elevenlabs;

  // Get API key from elevenlabs config or fall back to talk config
  const apiKey = elevenLabsConfig?.apiKey ?? cfg.talk?.apiKey;
  // Get voice ID from elevenlabs config or fall back to talk config
  const voiceId = elevenLabsConfig?.voiceId ?? cfg.talk?.voiceId;
  const modelId = elevenLabsConfig?.modelId ?? cfg.talk?.modelId ?? "eleven_monolingual_v1";

  if (!apiKey || !voiceId) {
    runtime.error?.("ElevenLabs TTS requires apiKey and voiceId");
    return undefined;
  }

  const id = crypto.randomUUID();
  const audioPath = path.join(os.tmpdir(), `clawdbot-reply-${id}.mp3`);

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    const response = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
      {
        method: "POST",
        headers: {
          "xi-api-key": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          text: trimmedText,
          model_id: modelId,
        }),
        signal: controller.signal,
      },
    );

    clearTimeout(timeout);

    if (!response.ok) {
      const error = await response.text();
      runtime.error?.(`ElevenLabs API error: ${response.status} - ${error}`);
      return undefined;
    }

    const buffer = Buffer.from(await response.arrayBuffer());
    await fs.writeFile(audioPath, buffer);

    if (shouldLogVerbose()) {
      logVerbose(`Synthesized audio via ElevenLabs: ${audioPath}`);
    }

    return { mediaUrls: [audioPath], audioAsVoice: true };
  } catch (err) {
    runtime.error?.(`Audio reply (elevenlabs) failed: ${String(err)}`);
    return undefined;
  }
}

/**
 * Synthesize audio using sag CLI (ElevenLabs wrapper)
 */
async function synthesizeViaSag(params: {
  cfg: ClawdbotConfig;
  trimmedText: string;
  timeoutMs: number;
  runtime: RuntimeEnv;
}): Promise<AudioReplyResult | undefined> {
  const { cfg, trimmedText, timeoutMs, runtime } = params;
  const replyConfig = cfg.audio?.reply;
  const sagConfig = replyConfig?.sag;

  const id = crypto.randomUUID();
  const audioPath = path.join(os.tmpdir(), `clawdbot-reply-${id}.mp3`);

  const args = ["tts"];

  if (sagConfig?.voice) {
    args.push("--voice", sagConfig.voice);
  }
  if (sagConfig?.model) {
    args.push("--model", sagConfig.model);
  }

  args.push("--text", trimmedText);
  args.push("--output", audioPath);

  try {
    if (shouldLogVerbose()) {
      logVerbose(`Synthesizing audio via sag: sag ${args.join(" ")}`);
    }
    await runExec("sag", args, {
      timeoutMs,
      maxBuffer: 5 * 1024 * 1024,
    });

    if (!(await fileExists(audioPath))) {
      runtime.error?.("sag TTS did not produce output file");
      return undefined;
    }

    return { mediaUrls: [audioPath], audioAsVoice: true };
  } catch (err) {
    runtime.error?.(`Audio reply (sag) failed: ${String(err)}`);
    return undefined;
  }
}
