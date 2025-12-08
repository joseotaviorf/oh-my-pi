## Enrich Emlio

### Purpose
This DAG creates enriched tables from models and services that use Emlio for logging.
It extract fields from Emlio's inputs.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator, after `emlio` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following tables in enrich layer, via full load:

- `p-click`
- `billboard`
- `citadel`
- `casio`
- `emma_watson`

​</details>
