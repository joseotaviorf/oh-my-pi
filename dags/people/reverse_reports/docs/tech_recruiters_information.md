# `tech_recruiters_information` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.tech_recruiters_information` |
| **Business owner** | Fernanda Bichuette (fernanda.bichuette@quintoandar.com.br) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Daily roster of active Tech employees with band, line, primary squad, manager, country, and tenure for P&T interviewer sheets. |
| **Business purpose** | Alternative to X-Ray for connecting P&T interviewer workbooks to employee attributes (work email, band, line, neotribe/squad, leader, country, tenure). Google Sheets remains the operational surface for that interviewer process ([PDA-532](https://quintoandar.atlassian.net/browse/PDA-532)). |
| **Business consumer** | Fernanda Bichuette / P&T team using the Tech recruiters information workbook. |
| **Operational source of truth** | Latest `metric_people.employee_snapshots` (`is_current` + `is_primary_assignment_for_snapshot`, active, vertical Tech). Primary squad (`neotribe`) from `dw_people.dim_product_tech_team.team_1` (team-formation sheet). |
| **Delivery channel** | Google Sheets tab **Sheet1** in workbook [https://docs.google.com/spreadsheets/d/1IT4SH0_iSfsSW7oJgaA0SezdHV31Enm93xvCij43YVg/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1IT4SH0_iSfsSW7oJgaA0SezdHV31Enm93xvCij43YVg/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Grain: one row per active Tech employee on the latest snapshot. Sheet headers follow the PDA-532 names (`email funcionário`, `banda`, `line`, `neotribe`, `lider`, `país`, `tempo de casa`). `neotribe` is `team_1` (primary squad); employees not on the team-formation roster export a NULL neotribe. Population is vertical Tech + active — not limited to interviewers. |
