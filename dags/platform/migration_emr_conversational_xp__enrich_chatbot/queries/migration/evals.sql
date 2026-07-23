WITH evals AS (
  SELECT
    id_session AS id_langfuse_session,
    MAP_FROM_ENTRIES(
      COLLECT_LIST(
        STRUCT(
          name,
          NAMED_STRUCT(
            'id', id_score,
            'value', value,
            'ts_created', ts_created
          )
        )
      )
    ) AS evals
  FROM
    datalake_langfuse_clean.scores
  WHERE
    ts_created >= '{load_start_date}'
    AND id_session IS NOT NULL
  GROUP BY 1
)
SELECT 
  e.id_langfuse_session,
  e.evals,
  s.ts_created
FROM
  evals AS e
LEFT JOIN
  datalake_chatbot.sessions AS s
    ON s.id_langfuse_session = e.id_langfuse_session
    AND s.ts_created >= '{load_start_date}'