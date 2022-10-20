## Enrich Rede Company

### Purpose

Creates tables for the context `enrich_rede_company`, enriching company information from Rede QuintoAndar. This data currently comes from HubSpot, but will be joined with the Company database in the future.

`company_sks` creates surrogate keys for the company dimension. These will be managed by us, and therefore will easily acommodate merging data from different sources.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, fully:
- `company_sks`
