## Enrich SAP Gateway

### Purpose

Used to deduplicate data from sap_gateway incremental tables. This service is the entrypoint for every financial transaction we do as QuintoAndar product team that needs to be accounted on our SAP system. SAP Gateway is an structure used to connect devices, environments, and platforms to SAP systems.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator, after `sap_gateway` DAG.

### Outputs

This pipeline produces the following output table on enrich layer:

- `feature`
- `operation`
- `sync_sap_job`

​</details>
