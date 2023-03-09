## Sindico Net

### Purpose

The purpose of the pipeline is to automate the process of collecting and organizing data from the SindicoNet API, making it easier to analyze and use in other applications, and to ensure the accuracy and consistency of the data over time. This pipeline is a part of Vespucio Project.

#### Documentation

[SindicoNet API](https://megacityoneapi.sindiconet.com.br/swagger/index.html)

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG runs daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Tables:

- datalake_sindico_net_raw.condominium
- datalake_sindico_net_clean.condominium

</details>