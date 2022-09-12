## Enrich PDD Payments

### Purpose

Creates enriched tables for the context `PDD` from Retsuko and Vans.
Each line is an invoice to be paid or paid.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `pdd_payments`
- `pdd_payments_monthly`

