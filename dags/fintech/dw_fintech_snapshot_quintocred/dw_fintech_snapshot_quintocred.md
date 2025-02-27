## DW Fintech Snapshot QuintoCred


### Purpose
​
This DAG creates a snapshot of several tables in order to provide "time travel" for QuintoCred Team.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered when execution_date is the first business day, monthly, via Mediator.

### Outputs

This pipeline produces the following output tables, in DW layer, incrementally:​​

- `dw_fintech_snapshot_quintocred.quintocred_aging_occurrence`
- `dw_fintech_snapshot_quintocred.quintocred_aging_recurring_payment_no_renewal`
- `dw_fintech_snapshot_quintocred.quintocred_aging_recurring_payment_renewal`
- `dw_fintech_snapshot_quintocred.quintocred_bad_debt`
- `dw_fintech_snapshot_quintocred.quintocred_ifrs_occurrence`
- `dw_fintech_snapshot_quintocred.quintocred_ifrs_recurring_payment`
- `dw_fintech_snapshot_quintocred.quintocred_payment_full`

  
​
</details>
