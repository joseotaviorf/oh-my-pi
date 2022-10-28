WITH 
wololo_calls AS (
  SELECT
      id AS id_contact,
      id_prospect_reference AS id_prospect_external,
      phone_number, 
      channel,
      id_analyst AS id_call_analyst,
      phone_output AS call_output, 
      ts_contacted
  FROM
      datalake_wololo_clean.contact
), 
wololo_round AS (
  SELECT 
      id_prospect, 
      id_reference,
      round_number,  
      round_max_tries, 
      ts_created AS ts_round_started,
      LEAD(ts_created, 1) OVER (PARTITION BY id_prospect ORDER BY ts_created ASC) AS ts_next_round_started
  FROM
    datalake_wololo_clean.round
)
SELECT
    pr.id AS id_prospect,
    wc.id_call_analyst,
    wc.phone_number,
    wc.channel,
    wc.call_output, 
    wr.round_number,
    ROW_NUMBER() OVER(PARTITION BY pr.id, wr.round_number ORDER BY wc.ts_contacted ASC) AS call_number,
    wr.round_max_tries,
    wc.ts_contacted,
    wr.ts_round_started,
    NOW() AS ts_load,
    YEAR(wc.ts_contacted) AS year,
    MONTH(wc.ts_contacted) AS month,
    DAY(wc.ts_contacted) AS day
FROM
    datalake_wololo_clean.prospect AS pr
INNER JOIN wololo_calls AS wc
     ON pr.id_reference = wc.id_prospect_external
LEFT JOIN wololo_round AS wr
     ON pr.id = wr.id_prospect
         AND (
             (wc.ts_contacted >= wr.ts_round_started AND wc.ts_contacted < wr.ts_next_round_started)
             OR 
             (wr.ts_next_round_started IS NULL AND wc.ts_contacted >= wr.ts_round_started)
         )
WHERE
    DATE(ts_contacted) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
