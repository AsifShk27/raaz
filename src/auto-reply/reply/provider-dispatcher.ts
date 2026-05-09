import {
  dispatchInboundMessageWithBufferedDispatcher,
  dispatchInboundMessageWithDispatcher,
} from "../dispatch.js";
import type {
  DispatchReplyWithBufferedBlockDispatcher,
  DispatchReplyWithDispatcher,
} from "./provider-dispatcher.types.js";
import { shouldSkipTextOnlyDelivery } from "./reply-dispatcher.js";

export type {
  DispatchReplyWithBufferedBlockDispatcher,
  DispatchReplyWithDispatcher,
} from "./provider-dispatcher.types.js";

export const dispatchReplyWithBufferedBlockDispatcher: DispatchReplyWithBufferedBlockDispatcher =
  async (params) => {
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
  };

export const dispatchReplyWithDispatcher: DispatchReplyWithDispatcher = async (params) => {
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
};
