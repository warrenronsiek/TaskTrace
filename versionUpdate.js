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

console.log(`Prepared release metadata at ${releaseMetadataPath}`);
console.log(`MARKETING_VERSION=${marketingVersion}`);
console.log(`CURRENT_PROJECT_VERSION=${currentProjectVersion}`);
