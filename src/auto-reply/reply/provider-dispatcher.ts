import type { ClawdbotConfig } from "../../config/config.js";
import type { RuntimeEnv } from "../../runtime.js";
import type { FinalizedMsgContext, MsgContext } from "../templating.js";
import type { GetReplyOptions } from "../types.js";
import type { DispatchInboundResult } from "../dispatch.js";
import {
  dispatchInboundMessageWithBufferedDispatcher,
  dispatchInboundMessageWithDispatcher,
} from "../dispatch.js";
import {
  shouldSkipTextOnlyDelivery,
  type ReplyDispatcherOptions,
  type ReplyDispatcherWithTypingOptions,
} from "./reply-dispatcher.js";

export async function dispatchReplyWithBufferedBlockDispatcher(params: {
  ctx: MsgContext | FinalizedMsgContext;
  cfg: ClawdbotConfig;
  dispatcherOptions: ReplyDispatcherWithTypingOptions;
  replyOptions?: Omit<GetReplyOptions, "onToolResult" | "onBlockReply">;
  replyResolver?: typeof import("../reply.js").getReplyFromConfig;
  /** Runtime for error logging. */
  runtime?: RuntimeEnv;
}): Promise<DispatchInboundResult> {
  const skipTextOnlyDelivery = shouldSkipTextOnlyDelivery(params.cfg, params.ctx.MediaType);

  return await dispatchInboundMessageWithBufferedDispatcher({
    ctx: params.ctx,
    cfg: params.cfg,
    dispatcherOptions: {
      ...params.dispatcherOptions,
      skipTextOnlyDelivery,
    },
    replyResolver: params.replyResolver,
    replyOptions: params.replyOptions,
    runtime: params.runtime,
  });
}

export async function dispatchReplyWithDispatcher(params: {
  ctx: MsgContext | FinalizedMsgContext;
  cfg: ClawdbotConfig;
  dispatcherOptions: ReplyDispatcherOptions;
  replyOptions?: Omit<GetReplyOptions, "onToolResult" | "onBlockReply">;
  replyResolver?: typeof import("../reply.js").getReplyFromConfig;
  /** Runtime for error logging. */
  runtime?: RuntimeEnv;
}): Promise<DispatchInboundResult> {
  const skipTextOnlyDelivery = shouldSkipTextOnlyDelivery(params.cfg, params.ctx.MediaType);

  return await dispatchInboundMessageWithDispatcher({
    ctx: params.ctx,
    cfg: params.cfg,
    dispatcherOptions: {
      ...params.dispatcherOptions,
      skipTextOnlyDelivery,
    },
    replyResolver: params.replyResolver,
    replyOptions: params.replyOptions,
    runtime: params.runtime,
  });
}
