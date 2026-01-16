<<<<<<< HEAD
import { chunkMarkdownTextWithMode, type ChunkMode } from "../../auto-reply/chunk.js";
import type { MarkdownTableMode } from "../../config/types.base.js";
import { convertMarkdownTables } from "../../markdown/tables.js";
=======
import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { chunkMarkdownText } from "../../auto-reply/chunk.js";
>>>>>>> 2a7fff29d (fix(voice): sag replies + opus voice notes; stabilize tool)
import type { ReplyPayload } from "../../auto-reply/types.js";
import { logVerbose, shouldLogVerbose } from "../../globals.js";
import { isVoiceCompatibleAudio } from "../../media/audio.js";
import { runExec } from "../../process/exec.js";
import { loadWebMedia } from "../media.js";
import { newConnectionId } from "../reconnect.js";
import { formatError } from "../session.js";
import { whatsappOutboundLog } from "./loggers.js";
import type { WebInboundMsg } from "./types.js";
import { elide } from "./util.js";

type VoiceTranscodeResult = {
  buffer: Buffer;
  contentType: string;
  fileName: string;
};

async function transcodeToOpus(params: {
  buffer: Buffer;
  fileName?: string;
}): Promise<VoiceTranscodeResult | null> {
  const id = randomUUID();
  const inputExt = params.fileName ? path.extname(params.fileName) : "";
  const inputPath = path.join(os.tmpdir(), `clawdbot-voice-in-${id}${inputExt || ".audio"}`);
  const outputPath = path.join(os.tmpdir(), `clawdbot-voice-out-${id}.ogg`);
  try {
    await fs.writeFile(inputPath, params.buffer);
    await runExec(
      "ffmpeg",
      [
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        inputPath,
        "-ac",
        "1",
        "-ar",
        "48000",
        "-c:a",
        "libopus",
        "-b:a",
        "24k",
        "-vbr",
        "on",
        outputPath,
      ],
      { timeoutMs: 30_000, maxBuffer: 5 * 1024 * 1024 },
    );
    const buffer = await fs.readFile(outputPath);
    return {
      buffer,
      contentType: "audio/ogg; codecs=opus",
      fileName: path.basename(outputPath),
    };
  } catch (err) {
    if (shouldLogVerbose()) {
      logVerbose(`Failed to transcode audio to opus: ${formatError(err)}`);
    }
    return null;
  } finally {
    await fs.unlink(inputPath).catch(() => {});
    await fs.unlink(outputPath).catch(() => {});
  }
}

export async function deliverWebReply(params: {
  replyResult: ReplyPayload;
  msg: WebInboundMsg;
  maxMediaBytes: number;
  textLimit: number;
  chunkMode?: ChunkMode;
  replyLogger: {
    info: (obj: unknown, msg: string) => void;
    warn: (obj: unknown, msg: string) => void;
  };
  connectionId?: string;
  skipLog?: boolean;
  tableMode?: MarkdownTableMode;
}) {
  const { replyResult, msg, maxMediaBytes, textLimit, replyLogger, connectionId, skipLog } = params;
  const replyStarted = Date.now();
  const tableMode = params.tableMode ?? "code";
  const chunkMode = params.chunkMode ?? "length";
  const convertedText = convertMarkdownTables(replyResult.text || "", tableMode);
  const textChunks = chunkMarkdownTextWithMode(convertedText, textLimit, chunkMode);
  const mediaList = replyResult.mediaUrls?.length
    ? replyResult.mediaUrls
    : replyResult.mediaUrl
      ? [replyResult.mediaUrl]
      : [];

  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  const sendWithRetry = async (fn: () => Promise<unknown>, label: string, maxAttempts = 3) => {
    let lastErr: unknown;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (err) {
        lastErr = err;
        const errText = formatError(err);
        const isLast = attempt === maxAttempts;
        const shouldRetry = /closed|reset|timed\\s*out|disconnect/i.test(errText);
        if (!shouldRetry || isLast) {
          throw err;
        }
        const backoffMs = 500 * attempt;
        logVerbose(
          `Retrying ${label} to ${msg.from} after failure (${attempt}/${maxAttempts - 1}) in ${backoffMs}ms: ${errText}`,
        );
        await sleep(backoffMs);
      }
    }
    throw lastErr;
  };

  // Text-only replies
  if (mediaList.length === 0 && textChunks.length) {
    const totalChunks = textChunks.length;
    for (const [index, chunk] of textChunks.entries()) {
      const chunkStarted = Date.now();
      await sendWithRetry(() => msg.reply(chunk), "text");
      if (!skipLog) {
        const durationMs = Date.now() - chunkStarted;
        whatsappOutboundLog.debug(
          `Sent chunk ${index + 1}/${totalChunks} to ${msg.from} (${durationMs.toFixed(0)}ms)`,
        );
      }
    }
    replyLogger.info(
      {
        correlationId: msg.id ?? newConnectionId(),
        connectionId: connectionId ?? null,
        to: msg.from,
        from: msg.to,
        text: elide(replyResult.text, 240),
        mediaUrl: null,
        mediaSizeBytes: null,
        mediaKind: null,
        durationMs: Date.now() - replyStarted,
      },
      "auto-reply sent (text)",
    );
    return;
  }

  const remainingText = [...textChunks];

  // Media (with optional caption on first item)
  for (const [index, mediaUrl] of mediaList.entries()) {
    const caption = index === 0 ? remainingText.shift() || undefined : undefined;
    try {
      const media = await loadWebMedia(mediaUrl, maxMediaBytes);
      if (shouldLogVerbose()) {
        logVerbose(
          `Web auto-reply media size: ${(media.buffer.length / (1024 * 1024)).toFixed(2)}MB`,
        );
        logVerbose(`Web auto-reply media source: ${mediaUrl} (kind ${media.kind})`);
      }
      if (media.kind === "image") {
        await sendWithRetry(
          () =>
            msg.sendMedia({
              image: media.buffer,
              caption,
              mimetype: media.contentType,
            }),
          "media:image",
        );
      } else if (media.kind === "audio") {
        const wantsVoice = replyResult.audioAsVoice !== false;
        let audioPayload = media;
        let useVoice = wantsVoice;
        if (
          wantsVoice &&
          !isVoiceCompatibleAudio({
            contentType: media.contentType,
            fileName: media.fileName,
          })
        ) {
          const converted = await transcodeToOpus({
            buffer: media.buffer,
            fileName: media.fileName,
          });
          if (converted) {
            audioPayload = {
              buffer: converted.buffer,
              contentType: converted.contentType,
              kind: "audio",
              fileName: converted.fileName,
            };
          } else {
            useVoice = false;
            if (shouldLogVerbose()) {
              logVerbose(
                "WhatsApp voice note requires OGG/Opus; sending audio as a file instead.",
              );
            }
          }
        }
        const voiceMimeType = "audio/ogg; codecs=opus";
        const mimetype = useVoice
          ? voiceMimeType
          : (audioPayload.contentType ?? "application/octet-stream");
        await sendWithRetry(
          () =>
            msg.sendMedia({
              audio: audioPayload.buffer,
              ptt: useVoice,
              mimetype,
              caption,
            }),
          "media:audio",
        );
      } else if (media.kind === "video") {
        await sendWithRetry(
          () =>
            msg.sendMedia({
              video: media.buffer,
              caption,
              mimetype: media.contentType,
            }),
          "media:video",
        );
      } else {
        const fileName = media.fileName ?? mediaUrl.split("/").pop() ?? "file";
        const mimetype = media.contentType ?? "application/octet-stream";
        await sendWithRetry(
          () =>
            msg.sendMedia({
              document: media.buffer,
              fileName,
              caption,
              mimetype,
            }),
          "media:document",
        );
      }
      whatsappOutboundLog.info(
        `Sent media reply to ${msg.from} (${(media.buffer.length / (1024 * 1024)).toFixed(2)}MB)`,
      );
      replyLogger.info(
        {
          correlationId: msg.id ?? newConnectionId(),
          connectionId: connectionId ?? null,
          to: msg.from,
          from: msg.to,
          text: caption ?? null,
          mediaUrl,
          mediaSizeBytes: media.buffer.length,
          mediaKind: media.kind,
          durationMs: Date.now() - replyStarted,
        },
        "auto-reply sent (media)",
      );
    } catch (err) {
      whatsappOutboundLog.error(`Failed sending web media to ${msg.from}: ${formatError(err)}`);
      replyLogger.warn({ err, mediaUrl }, "failed to send web media reply");
      if (index === 0) {
        const warning =
          err instanceof Error ? `⚠️ Media failed: ${err.message}` : "⚠️ Media failed.";
        const fallbackTextParts = [remainingText.shift() ?? caption ?? "", warning].filter(Boolean);
        const fallbackText = fallbackTextParts.join("\n");
        if (fallbackText) {
          whatsappOutboundLog.warn(`Media skipped; sent text-only to ${msg.from}`);
          await msg.reply(fallbackText);
        }
      }
    }
  }

  // Remaining text chunks after media
  for (const chunk of remainingText) {
    await msg.reply(chunk);
  }
}
