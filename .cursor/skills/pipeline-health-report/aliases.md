# Team aliases

Canonical **Airflow `line_name`** is `datalake_pipeline.line.line_name` / `dag.owner` in `*_declaration.yml`.

DEI **Incident Owner** (`customfield_12078`) uses slightly different labels and is often **empty** (field labelled *Incident Owner [DEPRECATED]*). Always query SLA/DQ with `line_name`; query Jira with the DEI label **and** by matching DAG names in the issue summary.

| User may say | Airflow `line_name` | DEI Incident Owner | DEI option id |
|--------------|---------------------|--------------------|---------------|
| People, Data People, Enterprise Engineering | `Data People` | Data People | `62530` |
| For Rent, ForRent, Data ForRent | `Data ForRent` | Data For Rent | `14714` |
| For Sale, ForSale, Data ForSale | `Data ForSale` | Data For Sale | `14715` |
| Fintech, Data Fintech | `Data Fintech` | Data Fintech | `16955` |
| Growth, Data Growth | `Data Growth` | Data Growth | `55173` |
| Agents, Data Agents | `Data Agents` | Data Agents | `60113` |
| S&S, SS, Data SS, Support | `Data SS` | Data S&S | `15755` |
| Governance, Data Governance | `Data Governance` | Data Governance | `14712` |
| Primitives, Data Primitives | `Data Primitives` | Data Primitives | `69331` |
| Serving, Data Serving | `Data Serving` | Data Serving | `69332` |
| Life Cycle, Data Life Cycle | `Data Life Cycle` | Data Life Cycle | `58334` |
| 3P, Data 3P Partners | `Data 3P Partners` | — | — |
| Data Engineering | `Data Engineering` | — | — |
| House and Listing | `Data House and Listing` | — | — |
| Broker XP | `Data Broker XP` | — | — |
| MLOps | *(not a pipeline line; quintoml DAGs)* | MLOps | `55171` |
| AE All | — | AE All | `16503` |

`is_data_line` in `datalake_pipeline.line` is a **subset** (ForRent, ForSale, Fintech, Growth, Agents, SS, Primitives, 3P, Data Engineering). **Do not** filter SLA on `is_data_line` — People, Governance, Serving, Life Cycle would disappear.

If `line_name` is missing from the table (new squad), use declaration `dag.owner` grep under `dags/` and still join `dag_sla_information` via those `id_dag`s.

## `id_dag` shape

Airflow / pipeline tables: `bietlejuice.<dag_name>`  
`dags/dependencies.yaml` keys and edges: same, plus task suffix after `:`.  
Grafana `cluster_name`: usually `<dag_name>` (no `bietlejuice.` prefix). EMR dashboard filter is `dag_name` (same value). Also match `{id_dag}_{run_id}` if that form appears.
