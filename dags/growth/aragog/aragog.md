## Aragog

### Purpose

This is a pipeline to collect and transform data from Aragog, QuintoAndar crawler microservice. With these pipeline, they can consume data from crawlers.

Important docs about Aragog:

- [Aragog Data RFC](https://docs.google.com/document/d/14uYCnlfF0_V_VhIFGo_mKVvwllpS1yYdx8mWirQEcX0/edit#heading=h.20gk8wb7m9e1)

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG runs daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Tables:

- datalake_aragog_raw.123i_condominium

- datalake_aragog_clean.123i_condominium

</details>