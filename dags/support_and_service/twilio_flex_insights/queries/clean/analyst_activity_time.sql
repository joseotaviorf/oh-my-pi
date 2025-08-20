SELECT
  agent_email AS analyst_email,
  agent_team AS analyst_twilio_team,
  CASE 
    WHEN activity = 'Pausa_PÃ³s-Atendimento' THEN 'Pausa_Pós-Atendimento'
    WHEN activity = 'DisponÃ­vel' THEN 'Disponível'
    WHEN activity = 'IndisponÃ­vel' THEN 'Indisponível'
    WHEN activity = 'Pausa_AlmoÃ§o' THEN 'Pausa_Almoço'
    WHEN activity = 'Pausa_ReuniÃ£o' THEN 'Pausa_Reunião'
    ELSE activity
  END AS activity,
  CAST(total_activity_time AS float) AS total_activity_time,
  date,
  year,
  month,
  day
FROM
  datalake_twilio_flex_insights_raw.analyst_activity_time
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')