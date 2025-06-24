## Enrich SAP

### Purpose

Creates enriched tables for SAP 4 HANA ERP from Clean layer. This enrich layer is mostly on purpose to remove duplicated data from Clean. Also added the `ledger` table, with data joined from all tables in the way most analysis would use.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `4hana_journal_entries_bank_account`
- `4hana_jornal_entries`
- `ledger_new_template`
- `ledger`
