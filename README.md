# icedq-tools/generate-mapping-action

GitHub composite Action that auto-generates a mapping file from an iceDQ export bundle by invoking [`@icedq/cli`](https://www.npmjs.com/package/@icedq/cli).

Pairs with [`icedq-tools/export-action`](https://github.com/marketplace/actions/icedq-export) and [`icedq-tools/import-action`](https://github.com/marketplace/actions/icedq-import) for zero-touch promotion pipelines.

## Usage

### Generate a mapping file from an export bundle

```yaml
- uses: actions/checkout@v4

- uses: icedq-tools/generate-mapping-action@v1
  with:
    icedq-base-url: ${{ vars.ICEDQ_BASE_URL }}
    keycloak-url:   ${{ vars.ICEDQ_KEYCLOAK_URL }}
    client-id:      ${{ secrets.ICEDQ_CLIENT_ID }}
    client-secret:  ${{ secrets.ICEDQ_CLIENT_SECRET }}
    org-id:         ${{ vars.ICEDQ_ORG_ID }}
    account-id:     ${{ vars.ICEDQ_ACCOUNT_ID }}
    workspace-id:   ${{ vars.ICEDQ_WORKSPACE_ID }}
    bundle:         ./bundle.zip
    output-file:    ./icedq-mapping.json
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
          icedq-base-url: ${{ vars.ICEDQ_BASE_URL }}
          keycloak-url:   ${{ vars.ICEDQ_KEYCLOAK_URL }}
          client-id:      ${{ secrets.ICEDQ_CLIENT_ID }}
          client-secret:  ${{ secrets.ICEDQ_CLIENT_SECRET }}
          org-id:         ${{ vars.ICEDQ_ORG_ID }}
          account-id:     ${{ vars.ICEDQ_ACCOUNT_ID }}
          workspace-id:   ${{ vars.ICEDQ_WORKSPACE_ID }}
          resource:       rule
          id:             ${{ vars.RULE_ID }}
          output-file:    ./exports/bundle.zip
          artifact-name:  icedq-bundle

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
          icedq-base-url: ${{ vars.ICEDQ_BASE_URL }}
          keycloak-url:   ${{ vars.ICEDQ_KEYCLOAK_URL }}
          client-id:      ${{ secrets.ICEDQ_CLIENT_ID }}
          client-secret:  ${{ secrets.ICEDQ_CLIENT_SECRET }}
          org-id:         ${{ vars.ICEDQ_ORG_ID }}
          account-id:     ${{ vars.ICEDQ_ACCOUNT_ID }}
          workspace-id:   ${{ vars.ICEDQ_WORKSPACE_ID }}
          bundle:         ./exports/bundle.zip
          output-file:    ./mappings/icedq-mapping.json
          artifact-name:  icedq-mapping

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
          icedq-base-url:        ${{ vars.ICEDQ_BASE_URL }}
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
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `icedq-base-url` | yes | — | iceDQ instance base URL |
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

`useFqn` is always written as `true`, since this action is built for the standard promotion-pipeline case, where the target workspace already has same-named counterparts for whatever you're importing (Dev → QA → UAT → Prod). Each resolved entry also gets a fixed action — `override` for connections and custom fields, `upsert` for parameters — the safe defaults for that same case. If you need different behavior (`useFqn: false`, or `append` for a parameter instead of replacing it), edit the generated file before passing it to `import-action`, or author one by hand — see [Mapping file reference](#mapping-file-reference) below for what every field and action actually does.

## Mapping file reference

### Field semantics

| Field | Is Required | Supported actions | What it does |
|---|---|---|---|
| `useFqn` | No | `true` / `false` | `true` when an asset (rule/workflow/folder) with the same name already exists in the target — this action always produces `true`. `false` when no same-named asset exists in target yet; only relevant if you're hand-authoring. |
| `connections` | No — omit this key (or the whole `mapping` object) when there's nothing to map | `override` only | Re-links the imported rule/workflow to use `newId` (target's connection) instead of `existingId` (source's connection). The target connection must already exist by name and connector type — if this action can't find a match, it throws error rather than writing a partial mapping file (see [How it works](#how-it-works)). |
| `parameters` | No — same as `connections` | `append`, `override`, `upsert` | `append` adds new keys to the target parameter without touching existing ones. `override` replaces the values of keys with matching names. `upsert` replaces matching keys and adds any new ones — this action always writes `upsert`. |
| `customFields` | No — same as `connections` | `override` only | Overrides the field's value in the target. The target field must already exist by name — unmatched fields are silently skipped by this action rather than failing the whole run. |

### Examples

**1. Connection only, no Parameters or Custom Fields**
```json
{
  "useFqn": true,
  "mapping": {
    "connections": [
      {
        "existingId": "conn-3e7788a3-69aa-546e-aee0-5e96156b968b",
        "newId": "conn-816eb590-ecef-5be3-9258-488e812328d3",
        "action": "override"
      }
    ]
  }
}
```

**2. Parameters — choosing `append` vs `override` vs `upsert`**

Every entry needs both `existingId` (source) and `newId` (target). This action itself always writes `upsert` — the other two only matter if you're hand-authoring or hand-editing the mapping file.

Say the source parameter `parameters_set_1` (exported with the rule) has:

| Key | Value |
|---|---|
| `dbkey` | `PROD` |
| `datekey` | `2/4/2025` |
| `typekey` | `Individual, Corporate` |
| `newkey` | `100` |

...and the target workspace's matching parameter already exists with different values, plus one key the source doesn't have at all:

| Key | Value |
|---|---|
| `dbkey` | `QA` |
| `datekey` | `1/1/2025` |
| `typekey` | `Individual` |
| `regionkey` | `US-EAST` |

- **`append`** — you're only introducing a *new* key this rule needs, and want a guarantee that nothing already in the target parameter can be touched — even if a name accidentally matches. Safest choice when the target's existing keys must never be overwritten. Could be in case of deploying a new rule or even an existing one where you added more keys in the same rule.
  ```json
  {
    "existingId": "parm-da473fee-a37e-5e9c-ad27-12436271abca",
    "newId":      "parm-e2d8f6c4-4a3b-5f9c-8d5e-7a9b2c3d4e5f",
    "action":     "append"
  }
  ```
  Resulting target parameter:

  | Key | Value | Outcome |
  |---|---|---|
  | `dbkey` | `QA` | unchanged — `append` never touches an existing key |
  | `datekey` | `1/1/2025` | unchanged |
  | `typekey` | `Individual` | unchanged |
  | `regionkey` | `US-EAST` | unchanged — source doesn't reference this key |
  | `newkey` | `100` | **added** — didn't exist in target yet |

- **`override`** — the target parameter already has a key with the same name (e.g. changing a `start_date` value), and you want to replace just that value. Unlike `upsert`, `override` never creates a new key — so it won't silently introduce something unexpected if the name doesn't actually match anything in target. Suitable when deploying an existing rule with an updated parameter value, where you specifically expect the target key to already be there.
  ```json
  {
    "existingId": "parm-da473fee-a37e-5e9c-ad27-12436271abca",
    "newId":      "parm-e2d8f6c4-4a3b-5f9c-8d5e-7a9b2c3d4e5f",
    "action":     "override"
  }
  ```
  Resulting target parameter:

  | Key | Value | Outcome |
  |---|---|---|
  | `dbkey` | `PROD` | **replaced** — matched key, value overwritten from source |
  | `datekey` | `2/4/2025` | **replaced** |
  | `typekey` | `Individual, Corporate` | **replaced** |
  | `regionkey` | `US-EAST` | unchanged — source doesn't reference this key |
  | *(`newkey` not added)* | — | `override` never creates a new key, even though source has one |

- **`upsert`** — you want the target to end up matching source for these keys regardless of current state: matching keys get replaced, missing keys get added. The safe "just make it match" default — why this action always chooses it automatically.
  ```json
  {
    "existingId": "parm-da473fee-a37e-5e9c-ad27-12436271abca",
    "newId":      "parm-e2d8f6c4-4a3b-5f9c-8d5e-7a9b2c3d4e5f",
    "action":     "upsert"
  }
  ```
  Resulting target parameter:

  | Key | Value | Outcome |
  |---|---|---|
  | `dbkey` | `PROD` | **replaced** |
  | `datekey` | `2/4/2025` | **replaced** |
  | `typekey` | `Individual, Corporate` | **replaced** |
  | `regionkey` | `US-EAST` | unchanged — source doesn't reference this key |
  | `newkey` | `100` | **added** — didn't exist in target yet |

**3. Full mapping** — connections, parameters, and custom fields together. Custom fields are matched and written by *name*, not UUID.

```json
{
  "useFqn": true,
  "mapping": {
    "connections": [
      {
        "existingId": "conn-b1075c0d-17e6-5cf3-b881-f2b9320f080f",
        "newId":      "conn-9e4a2f31-88bd-5c1e-a204-7d6e51b3a9c0",
        "action":     "override"
      }
    ],
    "parameters": [
      {
        "existingId": "parm-da473fee-a37e-5e9c-ad27-12436271abca",
        "newId":      "parm-e2d8f6c4-4a3b-5f9c-8d5e-7a9b2c3d4e5f",
        "action":     "upsert"
      }
    ],
    "customFields": [
      {
        "existingId": "sys_dq_dim",
        "newId":      "sys_dq_dim",
        "action":     "override"
      }
    ]
  }
}
```

### Tip: keep mapping files under version control

Whether generated by this action or hand-authored, commit mapping files to your repo (e.g. `mappings/qa.json`, `mappings/uat.json`, `mappings/prod.json`) so changes to UUID mappings are auditable and reviewable in pull requests, the same way you'd track any other config.

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
