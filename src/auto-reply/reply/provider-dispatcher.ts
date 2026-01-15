// MODIFIED FILE: src/auto-reply/reply/provider-dispatcher.ts
// Changes: Add runtime param, voiceOnly check, pass skipTextOnlyDelivery to dispatcher

import type { ClawdbotConfig } from "../../config/config.js";
import { logVerbose } from "../../globals.js";
import type { RuntimeEnv } from "../../runtime.js";
import type { MsgContext } from "../templating.js";
import { isAudio } from "../transcription.js";
import type { GetReplyOptions } from "../types.js";
import type { DispatchFromConfigResult } from "./dispatch-from-config.js";
import { dispatchReplyFromConfig } from "./dispatch-from-config.js";
import {
  createReplyDispatcher,
  createReplyDispatcherWithTyping,
  type ReplyDispatcherOptions,
  type ReplyDispatcherWithTypingOptions,
  shouldSkipTextOnlyDelivery,
} from "./reply-dispatcher.js";

export async function dispatchReplyWithBufferedBlockDispatcher(params: {
  ctx: MsgContext;
  cfg: ClawdbotConfig;
  dispatcherOptions: ReplyDispatcherWithTypingOptions;
  replyOptions?: Omit<GetReplyOptions, "onToolResult" | "onBlockReply">;
  replyResolver?: typeof import("../reply.js").getReplyFromConfig;
  // ============ ADDED FOR VOICE REPLY ============
  /** Runtime for error logging. Required for voice synthesis. */
  runtime?: RuntimeEnv;
  // ===============================================
}): Promise<DispatchFromConfigResult> {
  // ============ ADDED FOR VOICE REPLY ============
  // For voiceOnly mode: skip text delivery when inbound is audio and voiceOnly is enabled.
  // Text is still accumulated for voice synthesis, just not delivered to the user.
  const skipTextOnlyDelivery = shouldSkipTextOnlyDelivery(
    params.cfg,
    params.ctx.MediaType,
  );

  logVerbose(
    `voiceOnly check: MediaType=${params.ctx.MediaType} isAudio=${isAudio(params.ctx.MediaType)} voiceOnly=${params.cfg.audio?.reply?.voiceOnly === true} skipText=${skipTextOnlyDelivery}`,
  );
  // ===============================================

  const { dispatcher, replyOptions, markDispatchIdle } = createReplyDispatcherWithTyping({
    ...params.dispatcherOptions,
    // ============ ADDED FOR VOICE REPLY ============
    skipTextOnlyDelivery,
    // ===============================================
  });

  const result = await dispatchReplyFromConfig({
    ctx: params.ctx,
    cfg: params.cfg,
    dispatcher,
    replyResolver: params.replyResolver,
    // ============ ADDED FOR VOICE REPLY ============
    runtime: params.runtime,
    // ===============================================
    replyOptions: {
      ...params.replyOptions,
      ...replyOptions,
    },
  });

  markDispatchIdle();
  return result;
}

export async function dispatchReplyWithDispatcher(params: {
  ctx: MsgContext;
  cfg: ClawdbotConfig;
  dispatcherOptions: ReplyDispatcherOptions;
  replyOptions?: Omit<GetReplyOptions, "onToolResult" | "onBlockReply">;
  replyResolver?: typeof import("../reply.js").getReplyFromConfig;
  // ============ ADDED FOR VOICE REPLY ============
  /** Runtime for error logging. Required for voice synthesis. */
  runtime?: RuntimeEnv;
  // ===============================================
}): Promise<DispatchFromConfigResult> {
  // ============ ADDED FOR VOICE REPLY ============
  const skipTextOnlyDelivery = shouldSkipTextOnlyDelivery(
    params.cfg,
    params.ctx.MediaType,
  );
  // ===============================================

  const dispatcher = createReplyDispatcher({
    ...params.dispatcherOptions,
    // ============ ADDED FOR VOICE REPLY ============
    skipTextOnlyDelivery,
    // ===============================================
  });

  const result = await dispatchReplyFromConfig({
    ctx: params.ctx,
    cfg: params.cfg,
    dispatcher,
    replyResolver: params.replyResolver,
    // ============ ADDED FOR VOICE REPLY ============
    runtime: params.runtime,
    // ===============================================
    replyOptions: params.replyOptions,
  });

  await dispatcher.waitForIdle();
  return result;
}
