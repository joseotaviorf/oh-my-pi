## Reverse Nexxera

### Purpose

This DAG collects data from Datalake and sends to an S3 bucket used to be ingested in SAP.
Nexxera is a financial transaction ecosystem that connects companies, banks and acquirers through integrated banking automation service platforms, billing management, receipts, supplier relationship technologies and access to smart credit.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following table into the Datalake Reverse bucket, for backup pourposes:

- `OJDT`
- `JDT1`


This pipeline also exports results do Nexxera bucket (`s3://nexxera-{ENV}`).

For further information, please read [this documentation](https://docs.google.com/document/d/1ZQpHdTUPdi_gxhroiyHkJRYX96XM_8Y1_ggSKte69ds/edit#heading=h.20gk8wb7m9e1).

</details>
