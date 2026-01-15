import { z } from "zod";
import { AgentDefaultsSchema } from "./zod-schema.agent-defaults.js";
import { AgentEntrySchema } from "./zod-schema.agent-runtime.js";
import { TranscribeAudioSchema } from "./zod-schema.core.js";
import { isSafeExecutableValue } from "../infra/exec-safety.js";

export const AgentsSchema = z
  .object({
    defaults: z.lazy(() => AgentDefaultsSchema).optional(),
    list: z.array(AgentEntrySchema).optional(),
  })
  .strict()
  .optional();

export const BindingsSchema = z
  .array(
    z
      .object({
        agentId: z.string(),
        match: z
          .object({
            channel: z.string(),
            accountId: z.string().optional(),
            peer: z
              .object({
                kind: z.union([z.literal("dm"), z.literal("group"), z.literal("channel")]),
                id: z.string(),
              })
              .strict()
              .optional(),
            guildId: z.string().optional(),
            teamId: z.string().optional(),
          })
          .strict(),
      })
      .strict(),
  )
  .optional();

export const BroadcastStrategySchema = z.enum(["parallel", "sequential"]);

export const BroadcastSchema = z
  .object({
    strategy: BroadcastStrategySchema.optional(),
  })
  .catchall(z.array(z.string()))
  .optional();

export const AudioSchema = z
  .object({
    transcription: TranscribeAudioSchema,
    reply: z
      .object({
        command: z.array(z.string()).superRefine((value, ctx) => {
          const executable = value[0];
          if (!isSafeExecutableValue(executable)) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              path: [0],
              message: "expected safe executable name or path",
            });
          }
        }),
        timeoutSeconds: z.number().int().positive().optional(),
        voiceOnly: z.boolean().optional(),
      })
      .optional(),
  })
  .strict()
  .optional();
