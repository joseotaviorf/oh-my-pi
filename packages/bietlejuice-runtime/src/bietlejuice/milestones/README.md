# bietlejuice.milestones

Generic framework for **milestone_delta** loads: many strategy SQLs → one
Delta table keyed by consumer-chosen entity keys × `milestone_type`.

See local ADR: `.superpowers/milestone_delta_ingestion_adr.md` (not in git).
Entry Spark job: `dags/cross/base/spark_jobs/load_milestone_dimension.py`.
