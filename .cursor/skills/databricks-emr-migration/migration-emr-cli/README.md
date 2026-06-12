# migration-emr-cli (skill-local fork)

Fork of `packages/emr-cli` used **only** by the `databricks-emr-migration` skill.
This is not the official EMR CLI — do not use it for production DAG operations.

## Bootstrap

```bash
cd .cursor/skills/databricks-emr-migration/migration-emr-cli
make sync
make build-executable   # optional; uv run migration-emr-cli also works
```

## Auth

```bash
EMR_ENVIRONMENT=prod make weep-auth
```

Settings profile for validation: `config/migration-validate.yml`
