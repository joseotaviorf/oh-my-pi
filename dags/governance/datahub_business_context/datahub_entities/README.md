# Deprecated — entity YAML configs are no longer committed here.

Entity configs are generated ephemerally in CI from Markdown:

- Source: `docs/llm_context/business_entities/*.md`
- Generator: `packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py`
- Schema examples: `../reference/`

See `../README.md`.
