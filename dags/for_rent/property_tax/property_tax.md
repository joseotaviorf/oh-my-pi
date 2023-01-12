## Property Tax

### Purpose

This DAG brings [PropertyTax](https://github.com/quintoandar/property-tax) data, service responsible for updating municipal taxes for ongoing contracts.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw and clean, via incremental load:
 - `tax_report` - To avoid the duplicated column year in raw task, we're adding a sql file to use it to create the raw dataframe.