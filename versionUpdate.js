const fs = require('fs');
const path = require('path');

const releaseVersion = process.argv[2];

if (!releaseVersion) {
  console.error('Expected semantic-release version argument.');
  process.exit(1);
}

const match = releaseVersion.match(
  /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+.+)?$/
);

if (!match) {
  console.error(`Unsupported semantic version: ${releaseVersion}`);
  process.exit(1);
}

const [, majorPart, minorPart, patchPart, prereleasePart] = match;
const major = Number(majorPart);
const minor = Number(minorPart);
const patch = Number(patchPart);
const marketingVersion = `${major}.${minor}.${patch}`;
const prereleaseNumber = prereleasePart
  ? Number((prereleasePart.match(/(\d+)(?!.*\d)/) || ['0', '0'])[1])
  : 0;
const currentProjectVersion = String(
  major * 1000000000 + minor * 1000000 + patch * 1000 + prereleaseNumber
);

const releaseMetadataPath = path.join(process.cwd(), '.release-version.env');
const releaseMetadata = [
  `RELEASE_VERSION=${releaseVersion}`,
  `MARKETING_VERSION=${marketingVersion}`,
  `CURRENT_PROJECT_VERSION=${currentProjectVersion}`
].join('\n') + '\n';

fs.writeFileSync(releaseMetadataPath, releaseMetadata, 'utf8');

const updateJsonVersion = (relativePath) => {
  const filePath = path.join(process.cwd(), relativePath);
  if (!fs.existsSync(filePath)) {
    return;
  }

  const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  parsed.version = releaseVersion;
  fs.writeFileSync(filePath, `${JSON.stringify(parsed, null, 2)}\n`, 'utf8');
};

const updatePackageLockVersion = (relativePath) => {
  const filePath = path.join(process.cwd(), relativePath);
  if (!fs.existsSync(filePath)) {
    return;
  }

  const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  parsed.version = releaseVersion;

  if (parsed.packages && parsed.packages['']) {
    parsed.packages[''].version = releaseVersion;
  }

  fs.writeFileSync(filePath, `${JSON.stringify(parsed, null, 2)}\n`, 'utf8');
};

[
  'TaskTraceMCPPlugin/package.json',
  'TaskTraceMCPPlugin/openclaw.plugin.json',
  'TaskTraceMCPPlugin/.claude-plugin/plugin.json',
  'TaskTraceMCPPlugin/.codex-plugin/plugin.json',
  'TaskTraceMCPPlugin/.cursor-plugin/plugin.json'
].forEach(updateJsonVersion);

updatePackageLockVersion('TaskTraceMCPPlugin/package-lock.json');

console.log(`Prepared release metadata at ${releaseMetadataPath}`);
console.log(`MARKETING_VERSION=${marketingVersion}`);
console.log(`CURRENT_PROJECT_VERSION=${currentProjectVersion}`);
console.log(`TaskTraceMCPPlugin version=${releaseVersion}`);
