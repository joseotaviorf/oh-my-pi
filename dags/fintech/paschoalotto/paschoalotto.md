## Paschoalotto

Ingestion of Paschoalotto data saved in parquet format files stored in an S3 Bucket (s3://5a-paschoalotto). Paschoalotto is an external company that is responsible for the collection of defaulting customers.
The data will be used in the Collection Recovery analysis.
Tribe: Portfolio Management.


​<details>

  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw and clean, via full load:

- `cbparcelapagamento`
- `cbtiponegocio`
- `cbsituacaocontrato`
- `cbsitcontato`
- `cbetapa`
- `geqlcontato`
- `geqlemail`
- `geqlendereco`
- `geqlcontrato`

In datalake raw and clean, via incremental load:
- `cbpagamento`
- `cbfollowup`
- `cbbordero`
- `cbparcela`
- `cbcontrato`
- `cbitembordero`
