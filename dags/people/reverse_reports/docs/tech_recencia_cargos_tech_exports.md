# `recencia_cargos_tech` exports — reverse export governance

Batch migration of Daily Pipeline notebook `recencia_cargos_tech` ([DBP-1513](https://quintoandar.atlassian.net/browse/DBP-1513)). Unidirectional Google Sheets exports (no `gsheets_people` ingestion).

| Field | Value |
| --- | --- |
| **Metastore tables** | `reverse_reports.tech_recencia_cargos_*`, `reverse_reports.tech_ausencias_e_ferias_*` |
| **Business owner** | People Analytics — Leonardo Oliveira |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Monthly job/band tenure and approved absences for Tech & Product engineering workflows. |
| **Business purpose** | Refreshes leader-facing tenure and absence tabs used by Tech leaders and Tech HRBPs. Migrated from Exodus notebook `recencia_cargos_tech` to remove dependency on `base_fotografias_email_l` and legacy `dw_employee` absence tables. |
| **Business consumer** | Tech leaders and Tech HRBPs. |
| **Operational source of truth** | `metric_people.employee_snapshots` (`is_monthly_snapshot_for_employee` for tenure; `is_current_for_employee` for absence roster join); `dw_time.fact_absence_requests` + `dw_time.dim_absence_type` for absences. |
| **Delivery channel** | Multiple Google Sheets workbooks (see table below). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy column names preserved (`fechamento`, `id_colaborador`, `tempo_no_cargo_em_meses`, etc.). Monthly grain from `dt_month_reference` with `YEAR >= 2025`. Job tenure uses first monthly snapshot per `(assignment_number, job_name)` as role start. Band tenure (HRBP tab) uses latest month only. `TIMESTAMPDIFF(MONTH, …)` replaces legacy `DATE_DIFF(MONTH, …)` for EMR compatibility. |

## Export destinations

| Lake table | Sheet tab | Workbook |
| --- | --- | --- |
| `tech_recencia_cargos_ics_eng` | `recencia_cargos_ics_eng` | [Planilha 1](https://docs.google.com/spreadsheets/d/1POpQr6-LYpzO4gDwl5AgVBSZMcwvxLw-3NvJuxv4GLg) |
| `tech_recencia_cargos_ics_eng_mirror` | `recencia_cargos_ics_eng` | [Planilha 2](https://docs.google.com/spreadsheets/d/1zMPCPFW9N1Gj8Z6zJ9Sq_6pG1LzcnhoGKjoEb-b0y30) |
| `tech_recencia_cargos_ics_prod` | `recencia_cargos_ics_prod` | Planilha 1 |
| `tech_recencia_cargos_ics_prod_mirror` | `recencia_cargos_ics_prod` | Planilha 2 |
| `tech_ausencias_e_ferias_eng` | `ausencias_e_ferias` | Planilha 1 |
| `tech_ausencias_e_ferias_eng_mirror` | `ausencias_e_ferias` | Planilha 2 |
| `tech_ausencias_e_ferias_prod` | `ausencias_e_ferias_prod` | Planilha 1 |
| `tech_ausencias_e_ferias_prod_mirror` | `ausencias_e_ferias_prod` | Planilha 2 |
| `tech_recencia_cargos_tech_hrbps` | `tenures - tech` | [HRBP workbook](https://docs.google.com/spreadsheets/d/19bXBUPhld6tpfqmxt3OuRcUEvo3zgLh_nsx5pkKH5BY) |
| `tech_recencia_cargos_other_teams` | `recencia_cargos_other_verticals` | [Other verticals](https://docs.google.com/spreadsheets/d/1aMS17Z7YSFhEQT6HiRtvGhFyx9Qxk7_znkdOm1hEYmM) |

## L1 scope filters (legacy `l1_e` email)

| Export group | Filter |
| --- | --- |
| Engineering ICS + absences (eng) | `email_l1 = paulo.golgher@quintoandar.com.br` |
| Product ICS + absences (prod) | `email_l1 = rafael.castro@quintoandar.com.br` |
| HRBP band tenure | Paulo + Rafael L1 emails; latest month snapshot |
| Other verticals | Marco, Deborah, Ana, Lima, Nelzow, Macaya L1 emails |
