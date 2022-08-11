## SAP

### Purpose
This DAG creates the raw and clean layer for tables from SAP. 
SAP is a finance system whos responsible to manage all QuintoAndar accounting and finance transactions.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output table in the raw and clean layers:

- Via incremental load:
    - `incoming_payments`
    - `invoices`
    - `journal_entries`
    - `journal_entry_lines`
    - `other_entries`

</details>