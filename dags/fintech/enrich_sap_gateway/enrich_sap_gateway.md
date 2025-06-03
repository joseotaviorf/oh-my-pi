## Enrich SAP Gateway

### Purpose

Creates enriched tables for SAP Gateway from Clean layer. This enrich layer is mostly on purpose to extract informations from sap_payload json column of sync_sap_job table.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `sap_payload`
- `sap_payload_journal_entry_lines`