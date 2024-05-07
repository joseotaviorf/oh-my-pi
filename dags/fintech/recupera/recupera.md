## Recupera

Retrieves data from Recupera CSV files stored at a S3 bucket as zip files.

Read more about the tables and its fields at: https://drive.google.com/drive/folders/1n8kH6tkQHc67JzUGnEJFvR3M0vIWVF1v
Read more about the original and translated fields at: https://docs.google.com/spreadsheets/d/1yaqkdlfQPrQhW30L46miKKcLD99T4OV6svHJHXIYA6Q/edit#gid=965417697

​<details>

  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw and clean, via incremental load:

- `creditor_pending`
- `agreements_installment`
- `installment_canceled`
- `installment_detail`
- `records_distributed_channels`
- `complementary_records_written_down`
- `historical_records`
- `trato_feito_payment`
- `operational_records`

In datalake raw and clean, via full load:

- `contracts`
- `guarantor_contracts`
- `indicator_contracts`
- `historical`
- `detail_movement`
- `operators`
- `installment`
- `installments_indicators`
- `receipt`
- `records`
- `complementary_records`
- `email_records`
- `address_records`
- `indicator_records`
- `phone_records`
- `status`

</details>
