# `hub_pwd_ta_requisitions` — reverse export governance


| Field | Value |
| --- | --- |
| **Business owner** | People Insights and DE&I |
| **Technical owner** | People Insights (notebook owner: julia.mesquita@quintoandar.com.br). |
| **One-line summary** | Brazil TA requisitions (Greenhouse openings since 2025-11-01) for the DE&I PwD HUB hiring follow-up tab. |
| **Business purpose** | Feeds the PwD HUB Sheets workbook used by DE&I to track TA vacancies, including affirmative PwD focus. Kept on Google Sheets because DE&I still operates via Sheets/Looker Studio without full Superset access (same pattern as other DE&I reverse exports). Migrated from Daily Pipeline notebook `HUB_PwD.sql` ([DBP-1509](https://quintoandar.atlassian.net/browse/DBP-1509)). |
| **Business consumer** | DE&I  |
| **Delivery channel** | Google Sheets tab **base_ta** in workbook [https://docs.google.com/spreadsheets/d/1cC-q_8VHBEfkLnB4tSq5plLQudCLfNiFmGxRCy-9kDM/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1cC-q_8VHBEfkLnB4tSq5plLQudCLfNiFmGxRCy-9kDM/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy headers preserved. Status / `L1_hierarchy` / `diverse_hire_dimensions` ported from `People_Analytics/TA/base_requisitions_greenhouse` (offers → reserved, jobs.status → draft, demographics answers → diverse dimensions, hiring-manager → L1 via `employee_snapshots.name_l1`). Country from Greenhouse offices. Excludes openings with null `company`, placeholder code `000-00`, and sandbox-excluded requisitions `643` / `651`. `fl_system` = `GH`. |
