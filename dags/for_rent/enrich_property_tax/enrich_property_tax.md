## Enrich Property Tax

### Purpose

Creates enriched table for the context `PropertyTax`.
It deduplicates the records caused by incremental ingestion on raw/clean layer.
PropertyTax is a service that allows the PPs to update the IPTU value.

### Execution Interval
This DAG is triggered daily, via Mediator. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table, via full load:
- `tax_report`
