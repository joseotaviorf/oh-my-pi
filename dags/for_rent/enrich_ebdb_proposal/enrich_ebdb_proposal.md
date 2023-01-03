## Enrich EBDB Proposal

### Purpose

Creates enriched tables for the context `Proposal` of ebdb, like 
pre proposal.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, partitioned by `country_code`:

- `pre_proposal`
- `pre_proposal_aud`
- `proposal_person`
