## Webhelp

Ingestion of Webhelp data saved in parquet format files stored in an Azure Bucket (wasbs://lake-quinto-andar-sftp). Webhelp is an external company that is responsible for the collection of defaulting customers.
The data will be used in the Collection Recovery analysis.
Tribe: Portfolio Management.
Get more information at: https://drive.google.com/drive/u/0/folders/1KQu5e2Qk6Waa05S46kdUMZpnsm3vUQ0T

​<details>

  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw and clean, via full load:

- `historicos_clientes`
- `historicos_clientes_titulos`
- `login`
- `ocorrencias_clientes`
- `estagios`
- `titulos`
- `tipo_contrato`
- `credores`
- `parcelas`
- `devedores`
- `grupo_ocorrencias`
- `importacao`
