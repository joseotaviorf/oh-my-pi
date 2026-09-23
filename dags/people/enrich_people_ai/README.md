# People AI enrichment

## Purpose

`enrich_people_ai` produces governed People enrichments generated through the
internal LiteLLM gateway. The DAG writes Delta tables in `datalake_people` and
keeps product-specific prompt and response logic isolated from the shared
execution runner.

The current registered product is the Teva survey summary. The same DAG is
designed to host future products such as offboarding individual summaries and
offboarding executive summaries.

## Architecture

```text
tables_customization
        │
        ▼
run_ai_enrichment
        │
        ├── products/registry.py
        ├── products/<product>.py
        ├── products/ai_products.yml
        └── lib/llm_client.py → LiteLLM /chat/completions
```

The shared runner owns input selection, merge-key validation, model calls,
retry configuration, response collection, and Delta loading. A product adapter
owns its prompt, input payload, response parser, output schema, input table,
and merge grain.

LiteLLM is the required model access layer. Provider prefixes are part of the
LiteLLM model ID, for example:

```text
vertex_ai/claude-sonnet-4-5
bedrock/us.anthropic.claude-sonnet-4-6
```

The current client supports models exposed by LiteLLM through
`/chat/completions`. Models exposed only through the `responses` interface
require a separate client contract before they can be adopted.

## Product configuration

Operational settings live in
`spark_jobs/products/ai_products.yml`. The configuration is packaged with the
Spark job and contains:

- LiteLLM model ID;
- maximum calls per run;
- prompt version;
- default processing mode;
- temperature;
- maximum output tokens;
- request timeout;
- retry count.

Secrets are not stored in this file. The LiteLLM API key is resolved through
the configured People secret scope.

## Processing modes

The output table's `spark_job_arguments` selects the processing mode through
`--processing-mode`. The mode is evaluated against the target table before
calling the model:

| Mode | Behavior |
|---|---|
| `new_only` | Processes only input rows whose merge keys are absent from the target. |
| `unclassified` | Processes missing target rows and target rows whose product classification column is empty. |
| `all` | Processes every input row, including rows already classified, subject to `max_calls_per_run`. |

The Teva declaration currently uses `unclassified` and defines
`ai_executive_summary` as its classification column. Changing the declaration
to `all` intentionally regenerates existing summaries and updates their load
timestamps.

Every mode remains protected by `max_calls_per_run`. Increase that limit
deliberately for backfills because model calls incur cost and can extend the
EMR task duration.

## Teva output

`ai_teva_survey_summary` has one row per `survey_invite_id` and merges on that
key. The output contains the executive summary, four pillar narratives, the
additional-comments narrative, copied survey identifiers, and the UTC
generation timestamp.

The Teva prompt requires:

- a single valid JSON object;
- English output;
- no displayed calculations or averages;
- sentiment inference only when the Likert distribution supports it;
- explicit handling of insufficient data.

Invalid model responses are skipped and logged with a bounded response
preview. If no row in a run produces a valid response, the Spark task fails
instead of succeeding with an empty write.

## Adding a product

1. Create `spark_jobs/products/<product>.py`.
2. Define the product input table, merge keys, prompt builder, response parser,
   classification column, and output Spark schema.
3. Add operational settings to `spark_jobs/products/ai_products.yml`.
4. Register the adapter in `spark_jobs/products/registry.py`.
5. Add a table under `tables_customization` using
   `load_spark_job: run_ai_enrichment` and `--product <product>`.
6. Select `--processing-mode` in the declaration when the product needs a
   mode different from its YAML default.
7. Add metadata, data quality checks, and unit tests.
8. Regenerate DAG files with `make create-dag-files`.
9. Run the DAG successfully on Forno before merging.

Products with different grains or load semantics must use separate output
tables. For example, offboarding individual summaries and executive summaries
are separate products even if they use the same LiteLLM model.
