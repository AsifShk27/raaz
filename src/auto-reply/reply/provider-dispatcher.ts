import type { OpenClawConfig } from "../../config/config.js";
import type { DispatchInboundResult } from "../dispatch.js";
import {
  dispatchInboundMessageWithBufferedDispatcher,
  dispatchInboundMessageWithDispatcher,
} from "../dispatch.js";
import type { FinalizedMsgContext, MsgContext } from "../templating.js";
import type { GetReplyOptions } from "../types.js";
import type {
  ReplyDispatcherOptions,
  ReplyDispatcherWithTypingOptions,
} from "./reply-dispatcher.js";
import { shouldSkipTextOnlyDelivery } from "./reply-dispatcher.js";

export async function dispatchReplyWithBufferedBlockDispatcher(params: {
  ctx: MsgContext | FinalizedMsgContext;
  cfg: OpenClawConfig;
  dispatcherOptions: ReplyDispatcherWithTypingOptions;
  replyOptions?: Omit<GetReplyOptions, "onToolResult" | "onBlockReply">;
  replyResolver?: typeof import("../reply.js").getReplyFromConfig;
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
  });
}

export async function dispatchReplyWithDispatcher(params: {
  ctx: MsgContext | FinalizedMsgContext;
  cfg: OpenClawConfig;
  dispatcherOptions: ReplyDispatcherOptions;
  replyOptions?: Omit<GetReplyOptions, "onToolResult" | "onBlockReply">;
  replyResolver?: typeof import("../reply.js").getReplyFromConfig;
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
  });
}
