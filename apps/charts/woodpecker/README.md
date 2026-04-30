# woodpecker

Woodpecker CI server + agent (Kubernetes backend) integrated with Forgejo as the forge.

The agent runs pipeline steps as ephemeral Pods in the `prod` namespace — no DinD, no privileged containers. Istio sidecar injection is disabled on workflow Pods so they terminate cleanly when steps finish.

## Pipeline patterns

### Building OCI images (Kaniko)

Because the agent uses the Kubernetes backend, **DinD-style plugins like `plugins/docker` won't work without privilege**. Use [Kaniko](https://github.com/GoogleContainerTools/kaniko) instead — it builds OCI images rootless, with no daemon.

#### One-time setup (admin)

Create an **organization-level secret** in Woodpecker so every repo in the org gets registry auth for free:

1. Generate the auth blob locally — base64 of `username:PAT` (the PAT must have `write:package` scope on the Forgejo registry):
   ```bash
   printf 'morten-olsen:<your-PAT>' | base64
   ```
2. In the Woodpecker UI: your org → **Secrets → New** (or via `woodpecker-cli org secret add`):
   - **Name**: `forgejo_registry_auth`
   - **Value**: the base64 string from step 1
   - **Events**: `push`, `tag`, `manual`
   - **Images**: leave empty.

   > **Why no image filter?** Woodpecker only enforces image filters on _plugin steps_ (those using only `settings:`). Our Kaniko snippet uses `commands:` to write the auth config, which makes it a "normal step" — image filters don't apply, and the run will fail with `secret … is only allowed to be used by plugins`. In a single-tenant org the filter was defense-in-depth, not a real boundary; revisit it if you grow the org and need isolation between users.

#### Per-repo `.woodpecker.yaml`

```yaml
when:
  - event: [push, tag, manual]
    branch: main

steps:
  build_and_push:
    image: gcr.io/kaniko-project/executor:debug
    environment:
      AUTH:
        from_secret: forgejo_registry_auth
    commands:
      - mkdir -p /kaniko/.docker
      - printf '{"auths":{"code.olsen.cloud":{"auth":"%s"}}}' "$AUTH" > /kaniko/.docker/config.json
      - >
        /kaniko/executor
        --context=$CI_WORKSPACE
        --dockerfile=Dockerfile
        --destination=code.olsen.cloud/${CI_REPO}:latest
        --destination=code.olsen.cloud/${CI_REPO}:${CI_COMMIT_SHA:0:8}
        --label=org.opencontainers.image.source=https://code.olsen.cloud/${CI_REPO}
        --label=org.opencontainers.image.revision=${CI_COMMIT_SHA}
```

#### Notes

- Use the `:debug` variant — Kaniko's `:latest` is `scratch`-based with no shell, so `commands:` won't run. `:debug` ships with busybox.
- `${CI_REPO}` resolves to `<org>/<repo>` automatically — no per-repo edits needed.
- Tagging both `latest` and the short SHA gives you rollbacks for free.
- Don't add an explicit `clone:` step. Woodpecker clones implicitly; overriding `clone` replaces that built-in behaviour.
- The `org.opencontainers.image.source` label is what makes Forgejo auto-link the pushed image to the repo's **Packages** tab. Without it the image lands in the registry but stays orphaned from the repo UI.

## Migration from `plugins/docker`

If you have an existing `.woodpecker.yaml` with `plugins/docker`, you'll see:

> The formerly privileged plugin plugins/docker:latest is no longer privileged by default, if required, add it to WOODPECKER_PLUGINS_PRIVILEGED

Don't whitelist it — switch to the Kaniko snippet above. DinD on the K8s backend requires:
1. Whitelisting the image as privileged on the server (`WOODPECKER_PLUGINS_PRIVILEGED`),
2. Allowing privileged Pods on the agent's RBAC,
3. Operating a Docker daemon inside the worker Pod.

Kaniko sidesteps all three.
