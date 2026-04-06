# API Ingestion workflow documentation

English-language reference for the DAG Builder **`api_ingestion`** workflow (`workflow.type: api_ingestion`, raw layer).

| Document | Audience | Description |
|----------|----------|-------------|
| [user_guide.md](user_guide.md) | Pipeline authors | Declaration parameters, YAML examples, runtime behavior, limitations |
| [contributing.md](contributing.md) | Contributors | Code map (loader, Spark job, task creator, validator), extension checklist |

This folder was reviewed against the implementation on the default branch (Spark job `load_api_ingestion_raw`, `LoadAPIRawTaskCreator`, `APIConfigurationLoader`, `DAGDeclarationValidator`). Where YAML allows more than the runtime currently enforces, the user guide states that explicitly.
