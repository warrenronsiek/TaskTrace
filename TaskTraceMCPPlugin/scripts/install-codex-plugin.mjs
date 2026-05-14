import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");

const pluginName = "tasktrace-mcp";
const localMarketplaceName = "local-plugins";
const sourcePluginDir = repoRoot;
const marketplaceRootDir = path.join(os.homedir(), ".agents", "plugins");
const targetPluginRelativeDir = path.join(".codex", "plugins", pluginName);
const targetPluginDir = path.join(marketplaceRootDir, targetPluginRelativeDir);
const targetMarketplacePath = path.join(marketplaceRootDir, "marketplace.json");
const legacyPluginDir = path.join(os.homedir(), ".codex", "plugins", pluginName);
const codexPluginCacheRoot = path.join(os.homedir(), ".codex", "plugins", "cache");

async function copyIntoTarget(relativePath) {
  const src = path.join(sourcePluginDir, relativePath);
  const dest = path.join(targetPluginDir, relativePath);
  await fs.cp(src, dest, { recursive: true, force: true });
}

async function ensureDir(dirPath) {
  await fs.mkdir(dirPath, { recursive: true });
}

async function removeIfExists(targetPath) {
  await fs.rm(targetPath, { recursive: true, force: true });
}

async function removeInstalledCacheCopies() {
  const cacheCandidates = [path.join(codexPluginCacheRoot, localMarketplaceName, pluginName)];

  try {
    const marketplaceDirs = await fs.readdir(codexPluginCacheRoot, {
      withFileTypes: true,
    });
    for (const entry of marketplaceDirs) {
      if (!entry.isDirectory()) {
        continue;
      }
      cacheCandidates.push(path.join(codexPluginCacheRoot, entry.name, pluginName));
    }
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }

  await Promise.all(
    [...new Set(cacheCandidates)].map((cachePath) => removeIfExists(cachePath)),
  );
}

async function readJsonIfExists(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

function buildMarketplaceEntry() {
  return {
    name: pluginName,
    source: {
      source: "local",
      path: `./${targetPluginRelativeDir.split(path.sep).join("/")}`,
    },
    policy: {
      installation: "AVAILABLE",
      authentication: "ON_INSTALL",
    },
    category: "Productivity",
  };
}

async function installPluginBundle() {
  // Refresh the staged source bundle from scratch so local marketplace installs
  // always pick up the latest files from this checkout.
  await removeIfExists(targetPluginDir);
  // Clean up the legacy undocumented location used by older installer versions.
  await removeIfExists(legacyPluginDir);
  // If Codex already installed this local plugin, clear the cached copy so the
  // next install loads a fresh bundle from the staged source path.
  await removeInstalledCacheCopies();

  await ensureDir(targetPluginDir);
  await ensureDir(path.join(targetPluginDir, ".codex-plugin"));
  await fs.copyFile(
    path.join(sourcePluginDir, ".codex-plugin", "plugin.json"),
    path.join(targetPluginDir, ".codex-plugin", "plugin.json"),
  );
  await copyIntoTarget(".mcp.json");
  await copyIntoTarget("assets");
}

async function updateMarketplace() {
  await ensureDir(path.dirname(targetMarketplacePath));

  const marketplace =
    (await readJsonIfExists(targetMarketplacePath)) ?? {
      name: localMarketplaceName,
      interface: {
        displayName: "Local Plugins",
      },
      plugins: [],
    };

  if (!Array.isArray(marketplace.plugins)) {
    marketplace.plugins = [];
  }

  const entry = buildMarketplaceEntry();
  const existingIndex = marketplace.plugins.findIndex(
    (plugin) => plugin?.name === pluginName,
  );

  if (existingIndex >= 0) {
    marketplace.plugins[existingIndex] = entry;
  } else {
    marketplace.plugins.push(entry);
  }

  await fs.writeFile(
    targetMarketplacePath,
    `${JSON.stringify(marketplace, null, 2)}\n`,
    "utf8",
  );
}

async function main() {
  await installPluginBundle();
  await updateMarketplace();

  console.log(`Staged Codex plugin source at ${targetPluginDir}`);
  console.log(`Updated marketplace entry at ${targetMarketplacePath}`);
  console.log(
    "Removed any legacy or cached TaskTrace Codex plugin copies so the next Local Plugins install uses the latest staged bundle.",
  );
  console.log(
    "Restart Codex, verify the plugin appears in the local marketplace, then install tasktrace-mcp from Local Plugins.",
  );
}

await main();
