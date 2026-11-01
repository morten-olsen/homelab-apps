// Run in the pinned ci/renovate image: exercise Renovate's real replacement code
// without registry requests, credentials, or changes to the checkout.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { createRequire } = require('node:module');

const renovate = createRequire('/usr/local/renovate/package.json');
const JSON5 = renovate('json5');
const { getConfig } = renovate('./dist/config/defaults');
const { GlobalConfig } = renovate('./dist/config/global');
const { extractPackageFile } = renovate('./dist/modules/manager/custom/regex');
const { doAutoReplace } = renovate('./dist/workers/repository/update/branch/auto-replace');

async function main() {
  const config = JSON5.parse(await fs.readFile('renovate.json5', 'utf8'));
  const packageFile = 'apps/charts/forgejo/values.yaml';
  const manager = config.customManagers.find((entry) =>
    entry.managerFilePatterns.includes('/^apps/charts/forgejo/values\\.yaml$/'));
  assert.ok(manager, 'runner labels must remain discoverable');
  const original = (await fs.readFile(packageFile, 'utf8'))
    .replace(/@sha256:[a-f0-9]{64}/g, '');
  const { deps } = await extractPackageFile(original, packageFile, manager);
  assert.equal(deps.length, 5, 'discover all labels, including duplicate images');
  const localDir = await fs.mkdtemp(path.join(os.tmpdir(), 'renovate-label-test-'));
  GlobalConfig.set({ localDir });
  await fs.mkdir(path.join(localDir, path.dirname(packageFile)), { recursive: true });

  async function update(content, index, options) {
    const current = await extractPackageFile(content, packageFile, manager);
    return doAutoReplace({
      ...getConfig(), ...manager, ...current.deps[index],
      manager: 'regex', packageFile, depIndex: index,
      newValue: current.deps[index].currentValue,
      ...options,
    }, content, false);
  }

  try {
    let content = original;
    const firstDigest = `sha256:${'a'.repeat(64)}`;
    const secondDigest = `sha256:${'b'.repeat(64)}`;
    for (let index = 0; index < deps.length; index++) {
      content = await update(content, index, {
        isPinDigest: true, newDigest: firstDigest,
      });
    }
    const pinned = await extractPackageFile(content, packageFile, manager);
    assert.deepEqual(pinned.deps.map((dep) => dep.currentDigest), deps.map(() => firstDigest));
    assert.equal(content.replaceAll(`@${firstDigest}`, ''), original,
      'pinning preserves label names, image streams, and surrounding YAML');
    console.log('PASS: add missing digests to all five runner labels');

    for (let index = 0; index < deps.length; index++) {
      content = await update(content, index, { newDigest: secondDigest });
    }
    assert.equal(content.replaceAll(`@${secondDigest}`, ''), original);
    console.log('PASS: refresh existing digests, including duplicate labels');

    const index = deps.findIndex((dep) => dep.depName === 'code.forgejo.org/oci/docker');
    assert.ok(index >= 0);
    const updated = await update(content, index, { newValue: 'cli-next', newDigest: firstDigest });
    assert.equal(updated, content.replace(
      `docker://code.forgejo.org/oci/docker:cli@${secondDigest}`,
      `docker://code.forgejo.org/oci/docker:cli-next@${firstDigest}`));
    console.log('PASS: change tag and digest together without changing other labels');
  } finally {
    await fs.rm(localDir, { recursive: true, force: true });
  }
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
