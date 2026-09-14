## Reverse Nexxera

### Purpose

This DAG collects Nexxera reconciliation data from the datalake and sends CSV
files to an S3 bucket ingested by SAP. Nexxera connects companies, banks and
acquirers through banking automation, billing, receipts and supplier platforms.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Dataset-triggered after `bietlejuice.enrich_nexxera` (`load-enrich-dtw-filter`).
More information on run time [here]({chart_url}{dag_id}).

### Outputs

Reverse-layer backup in the datalake (`reverse/nexxera/`):

- `consolidated_entries` / `consolidated_header`
- `divergence_entries` / `divergence_header`
- `monthly_consolidated_entries` / `monthly_consolidated_header` (exported on day 1)
- `monthly_divergence_entries` / `monthly_divergence_header` (exported on day 1)

CSV export destination: `s3://{external_s3_bucket}` (`recon-credit-card-{ENV}`),
under `YYYY/MM/DD/daily/` or `YYYY/MM/DD/monthly/`, with
`bucket-owner-full-control`.

For further information, read [this documentation](https://docs.google.com/document/d/1ZQpHdTUPdi_gxhroiyHkJRYX96XM_8Y1_ggSKte69ds/edit#heading=h.20gk8wb7m9e1).

</details>
