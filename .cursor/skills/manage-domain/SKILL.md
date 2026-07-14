---
name: manage-domain
description: Add, rename, or deprecate a metadata `domain:` value in the single source of truth (domains.yml). Use when someone wants to create a new domain, rename an existing one, or remove/deprecate a domain from the FAIR/CI allowlist.
---

# Manage a metadata domain

The metadata `domain:` allowlist has **one source of truth**:

`packages/bietlejuice-core/src/bietlejuice/governance/domains.yml`

- `metadata_domains:` — the allowlisted `domain:` values (F2-01 + CI Yamale).
- `repo_folder_mappings:` — `dags/` folder → domain (only folders with a reliable 1:1).
- `deprecated_labels:` — old label → correct value (guidance only).

Every consumer derives from this file (runtime `constants.py` re-exports it; the 5 Yamale
`*_schema.yml` regexes are generated from it; `generate_metadata` resolves folders via it).
**Never edit the generated schemas or `constants.py` by hand.**

> `domains.yml` is owned by `@quintoandar/data-governance` (CODEOWNERS) — the PR
> needs their approval.

---

## Add a new domain

1. Append the display value to `metadata_domains:` in `domains.yml` (order is not
   significant for matching; append at the end).
2. If it maps 1:1 to a `dags/<folder>/`, add `folder: Display Value` to
   `repo_folder_mappings:`. If the folder is mixed/per-DAG (like `platform`, `core`),
   do **not** add it.
3. Regenerate the Yamale schemas: `make sync-domain-allowlist`.
4. Update the snapshot in the loader test so it matches the new list (it pins the exact
   pattern): `GOLDEN_PATTERN` in
   `packages/bietlejuice-core/test/unit/governance/test_domain_registry.py`.
5. Run the validation block below, then commit `domains.yml` + the regenerated
   `*_schema.yml` + the test together.

## Rename a domain

1. Change the value in `metadata_domains:` (and in `repo_folder_mappings:` if present).
2. Add `Old Name: New Name` to `deprecated_labels:`.
3. Steps 3–4 from "Add" (sync + update `GOLDEN_PATTERN`).
4. **Mass-migrate existing metadata** using the old value:
   ```bash
   rg -l "^domain:\s*Old Name\s*$" dags --glob '**/metadata/**/*.yml'
   ```
   Update each to the new value (same PR or a dedicated migration PR).
5. Validate + commit.

## Deprecate / remove a domain

1. Remove it from `metadata_domains:` (and `repo_folder_mappings:` if present).
2. Add it to `deprecated_labels:` pointing to the replacement.
3. Migrate existing usages (the `rg` step above) — CI will reject the removed value.
4. Sync + update `GOLDEN_PATTERN` + validate + commit.

---

## Validate before the PR

```bash
make sync-domain-allowlist              # regenerate the 5 Yamale schemas
make validate-domain-allowlist-sync     # --check: schemas in sync with domains.yml
uv run --directory packages/bietlejuice-core pytest test/unit/governance/ -q
make check-style
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
```

## What NOT to touch

The generated `*_schema.yml` `domain:` regex, `constants.py`
`METADATA_DOMAIN_CI_ALLOWLIST_*`, and any hardcoded domain list in docs — they all
derive from `domains.yml`. Change the source, run `make sync-domain-allowlist`, done.
