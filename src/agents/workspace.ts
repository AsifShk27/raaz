import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { isSubagentSessionKey } from "../routing/session-key.js";
import { runCommandWithTimeout } from "../process/exec.js";
import { resolveUserPath } from "../utils.js";

export function resolveDefaultAgentWorkspaceDir(
  env: NodeJS.ProcessEnv = process.env,
  homedir: () => string = os.homedir,
): string {
  const profile = env.CLAWDBOT_PROFILE?.trim();
  if (profile && profile.toLowerCase() !== "default") {
    return path.join(homedir(), `clawd-${profile}`);
  }
  return path.join(homedir(), "clawd");
}

export const DEFAULT_AGENT_WORKSPACE_DIR = resolveDefaultAgentWorkspaceDir();
export const DEFAULT_AGENTS_FILENAME = "AGENTS.md";
export const DEFAULT_SOUL_FILENAME = "SOUL.md";
export const DEFAULT_TOOLS_FILENAME = "TOOLS.md";
export const DEFAULT_IDENTITY_FILENAME = "IDENTITY.md";
export const DEFAULT_USER_FILENAME = "USER.md";
export const DEFAULT_HEARTBEAT_FILENAME = "HEARTBEAT.md";
export const DEFAULT_BOOTSTRAP_FILENAME = "BOOTSTRAP.md";

const DEFAULT_AGENTS_TEMPLATE = `# AGENTS.md - Clawdbot Workspace

This folder is the assistant's working directory.

## First run (one-time)
- If BOOTSTRAP.md exists, follow its ritual and delete it once complete.
- Your agent identity lives in IDENTITY.md.
- Your profile lives in USER.md.

## Backup tip (recommended)
If you treat this workspace as the agent's "memory", make it a git repo (ideally private) so identity
and notes are backed up.

\`\`\`bash
git init
git add AGENTS.md
git commit -m "Add agent workspace"
\`\`\`

## Safety defaults
- Don't exfiltrate secrets or private data.
- Don't run destructive commands unless explicitly asked.
- Be concise in chat; write longer output to files in this workspace.

## Daily memory (recommended)
- Keep a short daily log at memory/YYYY-MM-DD.md (create memory/ if needed).
- On session start, read today + yesterday if present.
- Capture durable facts, preferences, and decisions; avoid secrets.

## Heartbeats (optional)
- HEARTBEAT.md can hold a tiny checklist for heartbeat runs; keep it small.

## Customize
- Add your preferred style, rules, and "memory" here.
`;

const DEFAULT_SOUL_TEMPLATE = `# SOUL.md - Persona & Boundaries

Describe who the assistant is, tone, and boundaries.

- Keep replies concise and direct.
- Ask clarifying questions when needed.
- Never send streaming/partial replies to external messaging surfaces.
`;

const DEFAULT_TOOLS_TEMPLATE = `# TOOLS.md - User Tool Notes (editable)

This file is for *your* notes about external tools and conventions.
It does not define which tools exist; Clawdbot provides built-in tools internally.

## Examples

### imsg
- Send an iMessage/SMS: describe who/what, confirm before sending.
- Prefer short messages; avoid sending secrets.

### sag
- Text-to-speech: specify voice, target speaker/room, and whether to stream.

Add whatever else you want the assistant to know about your local toolchain.
`;

const DEFAULT_HEARTBEAT_TEMPLATE = `# HEARTBEAT.md

Keep this file empty unless you want a tiny checklist. Keep it small.
`;

const DEFAULT_BOOTSTRAP_TEMPLATE = `# BOOTSTRAP.md - First Run Ritual (delete after)

Hello. I was just born.

## Your mission
Start a short, playful conversation and learn:
- Who am I?
- What am I?
- Who are you?
- How should I call you?

## How to ask (cute + helpful)
Say:
"Hello! I was just born. Who am I? What am I? Who are you? How should I call you?"

Then offer suggestions:
- 3-5 name ideas.
- 3-5 creature/vibe combos.
- 5 emoji ideas.

## Write these files
After the user chooses, update:

1) IDENTITY.md
- Name
- Creature
- Vibe
- Emoji

2) USER.md
- Name
- Preferred address
- Pronouns (optional)
- Timezone (optional)
- Notes

3) ~/.clawdbot/clawdbot.json
Set identity.name, identity.theme, identity.emoji to match IDENTITY.md.

## Cleanup
Delete BOOTSTRAP.md once this is complete.
`;

const DEFAULT_IDENTITY_TEMPLATE = `# IDENTITY.md - Agent Identity

- Name:
- Creature:
- Vibe:
- Emoji:
`;

const DEFAULT_USER_TEMPLATE = `# USER.md - User Profile

- Name:
- Preferred address:
- Pronouns (optional):
- Timezone (optional):
- Notes:
`;

const TEMPLATE_DIR = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../docs/templates",
);

function stripFrontMatter(content: string): string {
  if (!content.startsWith("---")) return content;
  const endIndex = content.indexOf("\n---", 3);
  if (endIndex === -1) return content;
  const start = endIndex + "\n---".length;
  let trimmed = content.slice(start);
  trimmed = trimmed.replace(/^\s+/, "");
  return trimmed;
}

async function loadTemplate(name: string, fallback: string): Promise<string> {
  const templatePath = path.join(TEMPLATE_DIR, name);
  try {
    const content = await fs.readFile(templatePath, "utf-8");
    return stripFrontMatter(content);
  } catch {
    return fallback;
  }
}

const QMD_MEMORY_MASK = "**/*.md";
const QMD_INDEX_SUBDIR = path.join(".clawdbot", "qmd");

type QmdSearchHit = {
  file?: string;
  filepath?: string;
};

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizeCollectionName(input: string): string {
  const normalized = input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return normalized || "workspace";
}

function buildMemoryCollectionName(workspaceDir: string): string {
  const base = normalizeCollectionName(path.basename(workspaceDir));
  return `${base}_memory`;
}

function buildMemoryIndexPath(workspaceDir: string, collectionName: string): string {
  return path.join(workspaceDir, QMD_INDEX_SUBDIR, `${collectionName}.sqlite`);
}

function parseQmdSearchOutput(output: string): QmdSearchHit[] | null {
  const match = output.match(/\[[\s\S]*\]\s*$/);
  if (!match) return null;
  try {
    return JSON.parse(match[0]) as QmdSearchHit[];
  } catch {
    return null;
  }
}

function resolveQmdFilePath(memoryDir: string, fileRef?: string): string | null {
  if (!fileRef) return null;
  if (fileRef.startsWith("qmd://")) {
    const withoutScheme = fileRef.slice("qmd://".length);
    const slashIndex = withoutScheme.indexOf("/");
    if (slashIndex === -1) return null;
    const relativePath = withoutScheme.slice(slashIndex + 1);
    if (!relativePath) return null;
    const resolved = path.resolve(memoryDir, relativePath);
    const rel = path.relative(memoryDir, resolved);
    if (rel.startsWith("..") || path.isAbsolute(rel)) return null;
    return resolved;
  }
  const resolved = path.isAbsolute(fileRef)
    ? fileRef
    : path.resolve(memoryDir, fileRef);
  const rel = path.relative(memoryDir, resolved);
  if (rel.startsWith("..") || path.isAbsolute(rel)) return null;
  return resolved;
}

async function collectMarkdownFiles(dir: string): Promise<string[]> {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const results: string[] = [];
  for (const entry of entries) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...(await collectMarkdownFiles(entryPath)));
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      results.push(entryPath);
    }
  }
  return results;
}

async function getNewestMtimeMs(files: string[]): Promise<number | null> {
  let newest: number | null = null;
  for (const file of files) {
    try {
      const stat = await fs.stat(file);
      if (newest === null || stat.mtimeMs > newest) {
        newest = stat.mtimeMs;
      }
    } catch {
      // ignore missing files
    }
  }
  return newest;
}

async function runQmdCommand(
  args: string[],
  env: NodeJS.ProcessEnv,
  timeoutMs: number,
) {
  try {
    return await runCommandWithTimeout(["qmd", ...args], { timeoutMs, env });
  } catch {
    return null;
  }
}

async function tryQmdMemorySearch(params: {
  workspaceDir: string;
  memoryDir: string;
  memoryFiles: string[];
  newestMemoryMtimeMs: number | null;
  query: string;
  maxResults: number;
}): Promise<string[] | null> {
  if (!params.query || params.maxResults <= 0 || params.memoryFiles.length === 0) {
    return null;
  }
  const collectionName = buildMemoryCollectionName(params.workspaceDir);
  const indexPath = buildMemoryIndexPath(params.workspaceDir, collectionName);
  const indexDir = path.dirname(indexPath);

  try {
    await fs.mkdir(indexDir, { recursive: true });
  } catch {
    return null;
  }

  const env = { INDEX_PATH: indexPath };
  const listResult = await runQmdCommand(
    ["collection", "list"],
    env,
    8_000,
  );
  if (!listResult || listResult.code !== 0) return null;

  const collectionRegex = new RegExp(
    `^${escapeRegex(collectionName)} \\(qmd://`,
    "m",
  );
  const hasCollection = collectionRegex.test(listResult.stdout);
  let didUpdate = false;

  if (!hasCollection) {
    const addResult = await runQmdCommand(
      [
        "collection",
        "add",
        params.memoryDir,
        "--name",
        collectionName,
        "--mask",
        QMD_MEMORY_MASK,
      ],
      env,
      30_000,
    );
    if (!addResult || addResult.code !== 0) return null;
    didUpdate = true;
  } else if (params.newestMemoryMtimeMs) {
    const indexMtimeMs = await fs
      .stat(indexPath)
      .then((stat) => stat.mtimeMs)
      .catch(() => null);
    if (!indexMtimeMs || params.newestMemoryMtimeMs > indexMtimeMs) {
      const updateResult = await runQmdCommand(["update"], env, 30_000);
      if (updateResult && updateResult.code === 0) {
        didUpdate = true;
      }
    }
  }

  if (didUpdate) {
    await runQmdCommand(["embed"], env, 180_000);
  }

  const vsearchResult = await runQmdCommand(
    ["vsearch", params.query, "--json", "-n", String(params.maxResults)],
    env,
    60_000,
  );
  if (!vsearchResult || vsearchResult.code !== 0) return null;

  const hits = parseQmdSearchOutput(vsearchResult.stdout);
  if (!hits) return null;

  const memorySet = new Set(params.memoryFiles.map((file) => path.resolve(file)));
  const resolved: string[] = [];
  const seen = new Set<string>();

  for (const hit of hits) {
    const fileRef = hit.file ?? hit.filepath;
    const resolvedPath = resolveQmdFilePath(params.memoryDir, fileRef);
    if (!resolvedPath) continue;
    const normalized = path.resolve(resolvedPath);
    if (!memorySet.has(normalized)) continue;
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    resolved.push(normalized);
    if (resolved.length >= params.maxResults) break;
  }

  return resolved;
}

export type WorkspaceBootstrapFileName =
  | typeof DEFAULT_AGENTS_FILENAME
  | typeof DEFAULT_SOUL_FILENAME
  | typeof DEFAULT_TOOLS_FILENAME
  | typeof DEFAULT_IDENTITY_FILENAME
  | typeof DEFAULT_USER_FILENAME
  | typeof DEFAULT_HEARTBEAT_FILENAME
  | typeof DEFAULT_BOOTSTRAP_FILENAME
  | `memory/${string}`;

export type WorkspaceBootstrapFile = {
  name: WorkspaceBootstrapFileName;
  path: string;
  content?: string;
  missing: boolean;
};

async function writeFileIfMissing(filePath: string, content: string) {
  try {
    await fs.writeFile(filePath, content, {
      encoding: "utf-8",
      flag: "wx",
    });
  } catch (err) {
    const anyErr = err as { code?: string };
    if (anyErr.code !== "EEXIST") throw err;
  }
}

export async function ensureAgentWorkspace(params?: {
  dir?: string;
  ensureBootstrapFiles?: boolean;
}): Promise<{
  dir: string;
  agentsPath?: string;
  soulPath?: string;
  toolsPath?: string;
  identityPath?: string;
  userPath?: string;
  heartbeatPath?: string;
  bootstrapPath?: string;
}> {
  const rawDir = params?.dir?.trim()
    ? params.dir.trim()
    : DEFAULT_AGENT_WORKSPACE_DIR;
  const dir = resolveUserPath(rawDir);
  await fs.mkdir(dir, { recursive: true });

  if (!params?.ensureBootstrapFiles) return { dir };

  const agentsPath = path.join(dir, DEFAULT_AGENTS_FILENAME);
  const soulPath = path.join(dir, DEFAULT_SOUL_FILENAME);
  const toolsPath = path.join(dir, DEFAULT_TOOLS_FILENAME);
  const identityPath = path.join(dir, DEFAULT_IDENTITY_FILENAME);
  const userPath = path.join(dir, DEFAULT_USER_FILENAME);
  const heartbeatPath = path.join(dir, DEFAULT_HEARTBEAT_FILENAME);
  const bootstrapPath = path.join(dir, DEFAULT_BOOTSTRAP_FILENAME);

  const isBrandNewWorkspace = await (async () => {
    const paths = [
      agentsPath,
      soulPath,
      toolsPath,
      identityPath,
      userPath,
      heartbeatPath,
    ];
    const existing = await Promise.all(
      paths.map(async (p) => {
        try {
          await fs.access(p);
          return true;
        } catch {
          return false;
        }
      }),
    );
    return existing.every((v) => !v);
  })();

  const agentsTemplate = await loadTemplate(
    DEFAULT_AGENTS_FILENAME,
    DEFAULT_AGENTS_TEMPLATE,
  );
  const soulTemplate = await loadTemplate(
    DEFAULT_SOUL_FILENAME,
    DEFAULT_SOUL_TEMPLATE,
  );
  const toolsTemplate = await loadTemplate(
    DEFAULT_TOOLS_FILENAME,
    DEFAULT_TOOLS_TEMPLATE,
  );
  const identityTemplate = await loadTemplate(
    DEFAULT_IDENTITY_FILENAME,
    DEFAULT_IDENTITY_TEMPLATE,
  );
  const userTemplate = await loadTemplate(
    DEFAULT_USER_FILENAME,
    DEFAULT_USER_TEMPLATE,
  );
  const heartbeatTemplate = await loadTemplate(
    DEFAULT_HEARTBEAT_FILENAME,
    DEFAULT_HEARTBEAT_TEMPLATE,
  );
  const bootstrapTemplate = await loadTemplate(
    DEFAULT_BOOTSTRAP_FILENAME,
    DEFAULT_BOOTSTRAP_TEMPLATE,
  );

  await writeFileIfMissing(agentsPath, agentsTemplate);
  await writeFileIfMissing(soulPath, soulTemplate);
  await writeFileIfMissing(toolsPath, toolsTemplate);
  await writeFileIfMissing(identityPath, identityTemplate);
  await writeFileIfMissing(userPath, userTemplate);
  await writeFileIfMissing(heartbeatPath, heartbeatTemplate);
  if (isBrandNewWorkspace) {
    await writeFileIfMissing(bootstrapPath, bootstrapTemplate);
  }

  return {
    dir,
    agentsPath,
    soulPath,
    toolsPath,
    identityPath,
    userPath,
    heartbeatPath,
    bootstrapPath,
  };
}

export async function loadWorkspaceBootstrapFiles(
  dir: string,
  options?: {
    /** Optional query to retrieve relevant memory notes. */
    query?: string;
    /** Max memory files to attach (default: 3). */
    maxMemoryFiles?: number;
    /** Max bytes to include per memory file (default: 20k). */
    maxMemoryFileBytes?: number;
  },
): Promise<WorkspaceBootstrapFile[]> {
  const resolvedDir = resolveUserPath(dir);

  const entries: Array<{
    name: WorkspaceBootstrapFileName;
    filePath: string;
  }> = [
    {
      name: DEFAULT_AGENTS_FILENAME,
      filePath: path.join(resolvedDir, DEFAULT_AGENTS_FILENAME),
    },
    {
      name: DEFAULT_SOUL_FILENAME,
      filePath: path.join(resolvedDir, DEFAULT_SOUL_FILENAME),
    },
    {
      name: DEFAULT_TOOLS_FILENAME,
      filePath: path.join(resolvedDir, DEFAULT_TOOLS_FILENAME),
    },
    {
      name: DEFAULT_IDENTITY_FILENAME,
      filePath: path.join(resolvedDir, DEFAULT_IDENTITY_FILENAME),
    },
    {
      name: DEFAULT_USER_FILENAME,
      filePath: path.join(resolvedDir, DEFAULT_USER_FILENAME),
    },
    {
      name: DEFAULT_HEARTBEAT_FILENAME,
      filePath: path.join(resolvedDir, DEFAULT_HEARTBEAT_FILENAME),
    },
    {
      name: DEFAULT_BOOTSTRAP_FILENAME,
      filePath: path.join(resolvedDir, DEFAULT_BOOTSTRAP_FILENAME),
    },
  ];

  const memoryDir = path.join(resolvedDir, "memory");
  const query = options?.query?.trim();
  const maxMemoryFiles = options?.maxMemoryFiles ?? 3;
  const maxMemoryFileBytes = options?.maxMemoryFileBytes ?? 20_000;

  try {
    const memoryFiles = await collectMarkdownFiles(memoryDir);
    const newestMemoryMtimeMs = await getNewestMtimeMs(memoryFiles);
    const memoryMap = new Map<string, string>();

    for (const filePath of memoryFiles) {
      const rel = path
        .relative(memoryDir, filePath)
        .split(path.sep)
        .join("/");
      if (rel && !rel.startsWith("..")) {
        memoryMap.set(rel, filePath);
      }
    }

    const memoryEntries: string[] = [];

    if (query) {
      const qmdMatches =
        (await tryQmdMemorySearch({
          workspaceDir: resolvedDir,
          memoryDir,
          memoryFiles,
          newestMemoryMtimeMs,
          query,
          maxResults: maxMemoryFiles,
        })) ?? [];

      if (qmdMatches.length > 0) {
        memoryEntries.push(...qmdMatches);
      } else {
        const terms = query
          .toLowerCase()
          .split(/\s+/)
          .filter(Boolean);
        const scored: Array<{ filePath: string; score: number }> = [];
        for (const filePath of memoryFiles) {
          try {
            const content = await fs.readFile(filePath, "utf-8");
            const hay = content.toLowerCase();
            let score = 0;
            for (const term of terms) {
              if (term.length < 3) continue;
              if (hay.includes(term)) score += 1;
            }
            scored.push({ filePath, score });
          } catch {
            // ignore unreadable files
          }
        }
        scored
          .sort((a, b) => {
            if (b.score !== a.score) return b.score - a.score;
            return b.filePath.localeCompare(a.filePath);
          })
          .slice(0, maxMemoryFiles)
          .forEach((entry) => memoryEntries.push(entry.filePath));
      }
    } else {
      const always = [
        "trading-platform.md",
        "market-digest.md",
        "2026-01-09-lid-fix.md",
      ];
      for (const file of always) {
        const filePath = memoryMap.get(file);
        if (filePath) memoryEntries.push(filePath);
      }
    }

    const seen = new Set<string>();
    for (const filePath of memoryEntries) {
      const normalized = path.resolve(filePath);
      if (seen.has(normalized)) continue;
      seen.add(normalized);
      const rel = path
        .relative(memoryDir, normalized)
        .split(path.sep)
        .join("/");
      if (!rel || rel.startsWith("..")) continue;
      entries.push({
        name: `memory/${rel}`,
        filePath: normalized,
      });
    }
  } catch {
    // No memory directory; ignore.
  }

  const result: WorkspaceBootstrapFile[] = [];
  for (const entry of entries) {
    try {
      let content = await fs.readFile(entry.filePath, "utf-8");
      if (
        entry.name.startsWith("memory/") &&
        maxMemoryFileBytes > 0 &&
        content.length > maxMemoryFileBytes
      ) {
        content = content.slice(0, maxMemoryFileBytes);
      }
      result.push({
        name: entry.name,
        path: entry.filePath,
        content,
        missing: false,
      });
    } catch {
      result.push({ name: entry.name, path: entry.filePath, missing: true });
    }
  }
  return result;
}

const SUBAGENT_BOOTSTRAP_ALLOWLIST = new Set([
  DEFAULT_AGENTS_FILENAME,
  DEFAULT_TOOLS_FILENAME,
]);

export function filterBootstrapFilesForSession(
  files: WorkspaceBootstrapFile[],
  sessionKey?: string,
): WorkspaceBootstrapFile[] {
  if (!sessionKey || !isSubagentSessionKey(sessionKey)) return files;
  return files.filter((file) => SUBAGENT_BOOTSTRAP_ALLOWLIST.has(file.name));
}
