## DW SAP Accounting Process

​

### Purpose

​
This DAG creates the facts and dimensions models for SAP accounting process aka "The Straw" project.
​

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output model, in DW schema `sap_accounting_process`, via full load:​​

- `fact_sap_accounting_process`
​
</details>
