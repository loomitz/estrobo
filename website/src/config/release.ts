const repositoryUrl = "https://github.com/loomitz/estrobo";
const version = "0.1.0-beta.3";
const tag = `v${version}`;

export const release = {
  version,
  tag,
  repositoryUrl,
  releaseUrl: `${repositoryUrl}/releases/tag/${tag}`,
  dmgName: `estrobo-${tag}-macos-universal.dmg`,
  checksumName: "SHA256SUMS",
  manifestName: `estrobo-${tag}-manifest.json`,
} as const;

const downloadBaseUrl = `${repositoryUrl}/releases/download/${release.tag}`;

export const releaseDownloads = {
  dmg: `${downloadBaseUrl}/${release.dmgName}`,
  checksums: `${downloadBaseUrl}/${release.checksumName}`,
  manifest: `${downloadBaseUrl}/${release.manifestName}`,
} as const;
