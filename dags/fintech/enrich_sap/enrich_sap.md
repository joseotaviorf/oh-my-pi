## Enrich SAP

### Purpose

Creates enriched tables for SAP ERP from Clean layer. This enrich layer is mostly on purpose to remove duplicated data from Clean.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `incoming_payments`
- `invoice_lines`
- `journal_entries`
- `journal_entry_lines`
- `invoices`
- `incoming_payments_lines`
