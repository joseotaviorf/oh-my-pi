## Enrich Brokers Supply Processor

### Purpose

Creates enriched tables for the `Supply Processor` Product, responsible for managing Rede Supply leads.
Most of the fields, especially in `lead_3p`, are JSON strings, so it is convenient to extract the fields into proper columns.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `file`
- `lead_3p`