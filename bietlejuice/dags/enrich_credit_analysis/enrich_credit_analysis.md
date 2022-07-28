## Enrich Credit Analysis

### Purpose

Creates enriched tables for the `Credit Analysis` context. At the moment our main focus is to produce two visions here: One preseting dimensions and metrics at `id_proposal` granularity and another one in `id_credit_analysis` granularity.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `credit_analysis`
- `credit_analysis_proposals`