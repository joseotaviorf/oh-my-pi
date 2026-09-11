## Nexxera

Retrieves data from Nexxera CSV files available in s3 buckets.

​<details>

  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw and clean, via incremental load:

- `adjustments`
- `acquirer_header`
- `acquirer_trailer`
- `batch_header`
- `batch_trailer_030`
- `batch_trailer_050`
- `establishment_header`
- `establishment_trailer`
- `file_header`
- `file_trailer`
- `financial`
- `financial_extracts_030e`
- `financial_extracts_050e`
- `financial_legacy`
- `group_header`
- `group_trailer`
- `inadvance` (raw only; clean load disabled while the source has no `col_1 = 10` record)
- `payments_cnab`
- `sales`
- `transaction`

</details>
