# icedq-tools/generate-mapping-action

GitHub composite Action that auto-generates a mapping file from an iceDQ export bundle by invoking [`@icedq/cli`](https://www.npmjs.com/package/@icedq/cli).

Pairs with [`icedq-tools/export-action`](https://github.com/marketplace/actions/icedq-export) and [`icedq-tools/import-action`](https://github.com/marketplace/actions/icedq-import) for zero-touch promotion pipelines.

## Usage

### Generate a mapping file from an export bundle

```yaml
- uses: actions/checkout@v4

- uses: icedq-tools/generate-mapping-action@v1
  with:
    icedq-url:     ${{ secrets.ICEDQ_URL }}
    keycloak-url:  ${{ secrets.ICEDQ_KEYCLOAK_URL }}
    client-id:     ${{ secrets.ICEDQ_CLIENT_ID }}
    client-secret: ${{ secrets.ICEDQ_CLIENT_SECRET }}
    org-id:        ${{ secrets.ICEDQ_ORG_ID }}
    account-id:    ${{ secrets.ICEDQ_ACCOUNT_ID }}
    workspace-id:  ${{ vars.QA_WORKSPACE_ID }}
    bundle:        ./bundle.zip
    output-file:   ./icedq-mapping.json
```

### Full pipeline — export → generate-mapping → import

Each stage runs as a separate job with its own environment protection. The bundle and mapping file are passed between jobs via workflow artifacts.

```yaml
jobs:
  export:
    runs-on: ubuntu-latest
    environment: SOURCE
    outputs:
      task-id:     ${{ steps.export.outputs.task-id }}
      status:      ${{ steps.export.outputs.status }}
      bundle-path: ${{ steps.export.outputs.bundle-path }}
    steps:
      - uses: actions/checkout@v4

      - name: Export from Source environment
        id: export
        uses: icedq-tools/export-action@v1
        with:
          icedq-url:     ${{ vars.ICEDQ_URL }}
          keycloak-url:  ${{ vars.ICEDQ_KEYCLOAK_URL }}
          client-id:     ${{ secrets.ICEDQ_CLIENT_ID }}
          client-secret: ${{ secrets.ICEDQ_CLIENT_SECRET }}
          org-id:        ${{ vars.ICEDQ_ORG_ID }}
          account-id:    ${{ vars.ICEDQ_ACCOUNT_ID }}
          workspace-id:  ${{ vars.ICEDQ_WORKSPACE_ID }}
          resource:      rule
          id:            ${{ vars.RULE_ID }}
          output-file:   ./exports/bundle.zip
          artifact-name: icedq-bundle
          verify-ssl:    ${{ vars.ICEDQ_VERIFY_SSL }}

  generate-mapping:
    runs-on: ubuntu-latest
    needs: export
    environment: TARGET
    outputs:
      mapping-file: ${{ steps.mapping.outputs.mapping-file }}
    steps:
      - uses: actions/checkout@v4

      - name: Download bundle from export job
        uses: actions/download-artifact@v4
        with:
          name: icedq-bundle
          path: ./exports

      - name: Generate mapping for Target environment
        id: mapping
        uses: icedq-tools/generate-mapping-action@v1
        with:
          icedq-url:     ${{ vars.ICEDQ_URL }}
          keycloak-url:  ${{ vars.ICEDQ_KEYCLOAK_URL }}
          client-id:     ${{ secrets.ICEDQ_CLIENT_ID }}
          client-secret: ${{ secrets.ICEDQ_CLIENT_SECRET }}
          org-id:        ${{ vars.ICEDQ_ORG_ID }}
          account-id:    ${{ vars.ICEDQ_ACCOUNT_ID }}
          workspace-id:  ${{ vars.ICEDQ_WORKSPACE_ID }}
          bundle:        ./exports/bundle.zip
          output-file:   ./mappings/icedq-mapping.json
          artifact-name: icedq-mapping
          verify-ssl:    ${{ vars.ICEDQ_VERIFY_SSL }}

  import:
    runs-on: ubuntu-latest
    needs: [export, generate-mapping]
    environment: TARGET
    steps:
      - uses: actions/checkout@v4

      - name: Download bundle from export job
        uses: actions/download-artifact@v4
        with:
          name: icedq-bundle
          path: ./exports

      - name: Download mapping from generate-mapping job
        uses: actions/download-artifact@v4
        with:
          name: icedq-mapping
          path: ./mappings

      - name: Import into Target environment
        uses: icedq-tools/import-action@v1
        with:
          icedq-url:             ${{ vars.ICEDQ_URL }}
          keycloak-url:          ${{ vars.ICEDQ_KEYCLOAK_URL }}
          client-id:             ${{ secrets.ICEDQ_CLIENT_ID }}
          client-secret:         ${{ secrets.ICEDQ_CLIENT_SECRET }}
          org-id:                ${{ vars.ICEDQ_ORG_ID }}
          account-id:            ${{ vars.ICEDQ_ACCOUNT_ID }}
          workspace-id:          ${{ vars.ICEDQ_WORKSPACE_ID }}
          bundle:                ./exports/bundle.zip
          kind:                  rules
          mapping-file:          ./mappings/icedq-mapping.json
          strict:                false
          terminate-on-conflict: true
          verify-ssl:            ${{ vars.ICEDQ_VERIFY_SSL }}
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `icedq-url` | yes | — | iceDQ instance base URL |
| `keycloak-url` | yes | — | Keycloak token endpoint base |
| `client-id` | yes | — | OAuth client ID |
| `client-secret` | yes | — | OAuth client secret |
| `org-id` | yes | — | Org ID |
| `account-id` | yes | — | Account ID |
| `workspace-id` | yes | — | **Target** workspace ID (connections and parameters are resolved against this workspace) |
| `bundle` | yes | — | Path to the export ZIP (output of `export-action`) |
| `output-file` | no | `icedq-mapping.json` | Path to write the generated mapping JSON |
| `cli-version` | no | `latest` | Pin a specific `@icedq/cli` version |
| `verify-ssl` | no | `true` | Verify TLS |
| `upload-artifact` | no | `true` | Upload the mapping file as a workflow artifact |
| `artifact-name` | no | `icedq-mapping` | Name of the uploaded artifact |

## Outputs

| Output | Description |
|---|---|
| `mapping-file` | Path to the generated mapping JSON file |

## How it works

The action runs `icedq generate-mapping` which performs four steps against the **target** workspace:

1. Uploads the bundle to determine which connections, parameters, and custom fields need to be mapped
2. Searches the target workspace for connections matching by name (case-insensitive, per connector type) — fails if a connection is not found
3. Searches the target workspace for parameters matching by name — entries without a match are included without a `newId` so the import can upsert them
4. Searches the target workspace for custom fields matching by name — unmatched fields are skipped with a warning

The resulting mapping JSON (`useFqn: true`) is written to `output-file` and passed directly to `import-action` via `mapping-file`.

## Artifacts

When `upload-artifact` is `true` (the default), the generated mapping file is uploaded as a workflow artifact under `artifact-name`. This lets you inspect or archive the mapping used for each run.

## Versioning

- `@v1` — recommended. Tracks the latest `v1.x.y` release; you automatically get bug fixes and non-breaking improvements.
- `@v1.0.0` — pins to an exact release. No automatic updates; upgrade by changing this yourself.
- `@<commit-sha>` — pins to an exact commit. Most reproducible/secure option.

Breaking changes are released under a new major tag (`@v2`, etc.) — existing `@v1` users are never moved onto breaking changes automatically.

## Self-hosted runners

For iceDQ instances on private networks, set `runs-on: [self-hosted, icedq]` (or your runner's labels). The Action is runner-agnostic.

## Related tools

- [`icedq-tools/cli`](https://www.npmjs.com/package/@icedq/cli) — the CLI this Action wraps
- [`icedq-tools/export-action`](https://github.com/marketplace/actions/icedq-export) — exports a bundle from the source workspace
- [`icedq-tools/import-action`](https://github.com/marketplace/actions/icedq-import) — imports the bundle into the target workspace
