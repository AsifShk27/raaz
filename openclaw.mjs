#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import module from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// https://nodejs.org/api/module.html#module-compile-cache
if (module.enableCompileCache && !process.env.NODE_DISABLE_COMPILE_CACHE) {
  try {
    module.enableCompileCache();
  } catch {
    // Ignore errors
  }
}

const isModuleNotFoundError = (err) =>
  err && typeof err === "object" && "code" in err && err.code === "ERR_MODULE_NOT_FOUND";

const installProcessWarningFilter = async () => {
  // Keep bootstrap warnings consistent with the TypeScript runtime.
  for (const specifier of ["./dist/warning-filter.js", "./dist/warning-filter.mjs"]) {
    try {
      const mod = await import(specifier);
      if (typeof mod.installProcessWarningFilter === "function") {
        mod.installProcessWarningFilter();
        return;
      }
    } catch (err) {
      if (isModuleNotFoundError(err)) {
        continue;
      }
      throw err;
    }
  }
};

await installProcessWarningFilter();
const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const wrapperPath =
  process.env.OPENCLAW_WITH_TTS_WRAPPER ??
  "/home/shkas/projects/raaz/skills/tts-server-directml/scripts/openclaw-with-tts.sh";

const main = async () => {
  const isGatewayCommand = args[0] === "gateway" || args[0] === "daemon";
  const shouldWrap = isGatewayCommand && process.env.OPENCLAW_WRAPPED !== "1";
  if (shouldWrap && fs.existsSync(wrapperPath)) {
    const env = {
      ...process.env,
      OPENCLAW_WRAPPED: "1",
      OPENCLAW_BIN: path.join(here, "openclaw.mjs"),
    };
    const child = spawn(wrapperPath, args, {
      cwd: here,
      env,
      stdio: "inherit",
    });
    await new Promise((resolve) => {
      child.on("exit", (exitCode, exitSignal) => {
        if (exitSignal) {
          process.exit(1);
        }
        process.exit(exitCode ?? 1);
      });
      child.on("close", resolve);
    });
    return;
  }

  const entryCandidates = [
    path.join(here, "dist", "entry.js"),
    path.join(here, "dist", "entry.mjs"),
    path.join(here, "dist", "index.mjs"),
    path.join(here, "dist", "index.js"),
  ];
  const entryPath = entryCandidates.find((candidate) => fs.existsSync(candidate));
  if (!entryPath) {
    throw new Error(
      "OpenClaw build output missing. Expected dist/entry.(m)js or dist/index.(m)js. Run `pnpm build`.",
    );
  }

  // Ensure the imported entry sees itself as the main module (isMainModule check).
  if (!process.argv[1] || path.resolve(process.argv[1]) !== path.resolve(entryPath)) {
    process.argv[1] = entryPath;
  }

  await import(pathToFileURL(entryPath).href);
};

await main();
