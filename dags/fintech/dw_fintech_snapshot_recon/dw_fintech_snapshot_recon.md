## DW Fintech Snapshot Recon

### Purpose

This DAG creates monthly snapshots of accounting funnel, contract recon, Robin Hood accounting entries, and rental guarantee data for finance reconciliation and time travel.

### Execution interval

This DAG is triggered when `execution_date` is the first business day of the month, via Mediator (same pattern as `dw_fintech_snapshot`).

### Outputs

Incremental Delta tables in `dw_fintech_snapshot_recon`:

- `dw_fintech_snapshot_recon.cap_union_invoice_snapshot`
- `dw_fintech_snapshot_recon.contract_recon_snapshot`
- `dw_fintech_snapshot_recon.robin_hood_accounting_entry_snapshot`
- `dw_fintech_snapshot_recon.rental_guarantee_snapshot`

Partition columns: `year`, `month`, `day` (from `CURRENT_DATE()` at snapshot run). `ts_snapshot` is `NOW()` at run time.
