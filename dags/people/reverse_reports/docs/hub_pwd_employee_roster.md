# `hub_pwd_employee_roster` — reverse export governance


| Field | Value |
| --- | --- |
| **Business owner** | People Insights and DE&I |
| **Technical owner** | People Insights (notebook owner: julia.mesquita@quintoandar.com.br). |
| **One-line summary** | Active Brazil employee roster with PwD medical-record flag and L1/L2 managers for the DE&I PwD HUB. |
| **Business purpose** | Feeds the PwD HUB Sheets workbook used by DE&I to track how many PwDs are in the company and where they sit in the org structure. Kept on Google Sheets because DE&I still operates via Sheets/Looker Studio without full Superset access (same pattern as other DE&I reverse exports). Migrated from Daily Pipeline notebook `HUB_PwD.sql` ([DBP-1509](https://quintoandar.atlassian.net/browse/DBP-1509)). |
| **Business consumer** | DE&I  |
| **Delivery channel** | Google Sheets tab **base_completa** in workbook [https://docs.google.com/spreadsheets/d/1cC-q_8VHBEfkLnB4tSq5plLQudCLfNiFmGxRCy-9kDM/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1cC-q_8VHBEfkLnB4tSq5plLQudCLfNiFmGxRCy-9kDM/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy headers preserved (`id_colaborador`, `status`, `pcd_laudo`, `l1_gestor`, `l2_gestor`, `pais`). Grain: one row per primary active assignment in Brazil. `id_colaborador` = `LOWER(assignment_number)`. Country exported as `brasil`. |
