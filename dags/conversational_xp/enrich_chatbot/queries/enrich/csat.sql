SELECT
  r.id_origin AS id_session,
  r.id_user,
  ss.agent,
  r.grade AS rating,
  r.comment,
  r.ts_created
FROM
  datalake_chat_fup_clean.rating AS r
LEFT JOIN
  datalake_sauron_clean.session AS ss
    ON ss.id = r.id_origin
WHERE
  r.ts_created >= '{load_start_date}'
