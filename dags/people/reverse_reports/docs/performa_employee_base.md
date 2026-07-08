# `performa_employee_base` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.performa_employee_base` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Full employee roster exported daily to Google Sheets for the Performa performance objectives dashboard, with quarterly granularity. |
| **Business purpose** | Provides all employees (active and recently terminated) with their management hierarchy, job, and org-unit metadata so the Performa tool can route performance objectives and display org-chart access controls. Each employee row is repeated once per fiscal quarter (Q1–Q4) to support quarterly cycle views. |
| **Business consumer** | Performa. |
| **Delivery channel** | Google Sheets tab **base_dash (Não apagar)** in workbook [https://docs.google.com/spreadsheets/d/1RO7I-zXLLNKhpIiSxBumbFxtog84xGvvzktEpJNpKO8/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1RO7I-zXLLNKhpIiSxBumbFxtog84xGvvzktEpJNpKO8/edit?usp=sharing). Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
