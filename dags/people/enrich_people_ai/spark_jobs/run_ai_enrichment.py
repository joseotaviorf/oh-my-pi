"""Generic Spark entrypoint for configured People AI enrichment products.

The implementation is kept in the legacy module for compatibility with its
existing unit-test imports. The DAG should invoke this module so future
products use the same configured runner without adding another entrypoint.
"""

from dags.people.enrich_people_ai.spark_jobs.generate_ai_teva_survey_summary import main

if __name__ == "__main__":
    main()
