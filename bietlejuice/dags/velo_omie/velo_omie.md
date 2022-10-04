## Velo Omie

### Purpose

Velo is one of QuintoAndar's acquisitions, and this DAG is responsible for data ingestion from Velo's records on Omie ERP.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw:

- `cash_flows` (incremental)
- `categories` (full load)
- `projects` (full load)
- `bank_account` (full load)

In datalake clean:

- `cash_flows`
- `categories`
- `projects`
- `bank_account`
