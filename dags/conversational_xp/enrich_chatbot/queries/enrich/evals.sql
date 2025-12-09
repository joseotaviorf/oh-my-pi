SELECT
  sc.id_session AS id_langfuse_session,
  MAP_FROM_ENTRIES(
    COLLECT_LIST(
      STRUCT(
        sc.name,
        NAMED_STRUCT(
          'id', sc.id_score,
          'value', sc.value,
          'ts_created', sc.ts_created
        )
      )
    )
  ) AS evals
FROM
  datalake_langfuse_clean.scores AS sc
WHERE
  sc.ts_created >= '{load_start_date}'
GROUP BY 1