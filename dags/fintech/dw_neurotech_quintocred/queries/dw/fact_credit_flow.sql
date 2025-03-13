WITH
base_union AS (
SELECT
    id_propose,
    rating,
    status,
    user,
    main_proponent_name,
    is_last_register,
    dt_propose,
    ts_begin,
    ts_end,
    ts_operation
FROM
    datalake_neurotech_quintocred.credit_evaluation

UNION ALL

SELECT
    id_propose,
    rating,
    status,
    user,
    main_proponent_name,
    is_last_register,
    dt_propose,
    ts_begin,
    ts_end,
    ts_operation
FROM
    datalake_neurotech_quintocred.manual_evaluation
),
lag_table AS (
SELECT
    id_propose AS sk_propose,
    rating,
    status,
    user,
    main_proponent_name,
    is_last_register,
    dt_propose,
    ts_begin,
    ts_end,
    ts_operation,
    LAG(status, 1) OVER(PARTITION BY id_propose ORDER BY ts_begin ASC) AS previous_status,
    LAG(status, 2) OVER(PARTITION BY id_propose ORDER BY ts_begin ASC) AS previous_status_2,
    LAG(ts_begin, 1) OVER(PARTITION BY id_propose ORDER BY ts_begin ASC) AS previous_date_begin,
    LAG(ts_begin, 2) OVER(PARTITION BY id_propose ORDER BY ts_begin ASC) AS previous_date_begin_2,
    LAG(status, 1) OVER(PARTITION BY id_propose ORDER BY ts_begin DESC) AS next_status,
    SUBSTR(CAST(ts_end AS STRING),12,5) AS hr_end,
    CASE
      WHEN dd.weekday_name = 'Saturday' AND SUBSTR(CAST(ts_begin AS STRING),12,5) > '12:00' THEN '12:00'
      ELSE SUBSTR(CAST(ts_begin AS STRING),12,5)
    END hr_begin_adjusted,
    ROW_NUMBER() OVER (PARTITION BY id_propose ORDER BY ts_begin ASC) AS rank_table
FROM
    base_union b
LEFT JOIN
    dw_public.dim_date dd
    ON DATE(b.ts_begin) = dd.date
),
cte_base_credito AS (
SELECT
    *,
    CASE
        WHEN previous_status = 'RESSUBMISSAO' THEN 'HORÁRIO AJUSTADO'
        ELSE NULL
    END AS flag_adjusted,
    CASE
        WHEN previous_status_2 = 'RESSUBMISSAO' AND previous_status = 'RESSUBMISSAO' AND DATE_DIFF(MINUTE, previous_date_begin_2,ts_begin) < 40 THEN previous_date_begin_2
        WHEN previous_status = 'RESSUBMISSAO' AND DATE_DIFF(MINUTE, previous_date_begin,ts_begin) < 40 THEN previous_date_begin
        ELSE ts_begin
    END AS ts_begin_adjusted,
    SUBSTR(CAST(CASE
        WHEN previous_status_2 = 'RESSUBMISSAO' AND previous_status = 'RESSUBMISSAO' AND DATE_DIFF(MINUTE, previous_date_begin_2,ts_begin) < 40 THEN previous_date_begin_2
        WHEN previous_status = 'RESSUBMISSAO' AND DATE_DIFF(MINUTE, previous_date_begin,ts_begin) < 40 THEN previous_date_begin
        ELSE ts_begin
    END AS STRING),12,5) AS hr_begin
FROM
    lag_table
)

SELECT
    sk_propose,
    rating,
    status,
    user,
    main_proponent_name,
    previous_status,
    previous_status_2,
    previous_date_begin,
    previous_date_begin_2,
    next_status,
    CASE
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 0 AND hr_begin BETWEEN '08:00' AND '18:59' AND sabado.weekday_name IN('Monday','Tuesday','Wednesday','Thursday','Friday') THEN DATE_DIFF(SECOND, ts_begin_adjusted,ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 0 AND hr_begin BETWEEN '08:00' AND '11:59' AND sabado.weekday_name IN('Saturday') THEN DATE_DIFF(SECOND, ts_begin_adjusted,ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 0 AND hr_begin < '08:00' AND hr_end < '08:00' AND sabado.weekday_name IN('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday') THEN DATE_DIFF(SECOND, ts_begin_adjusted,ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 0 AND hr_begin < '08:00' AND hr_end >= '08:00' AND sabado.weekday_name IN('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday') THEN DATE_DIFF(SECOND,CAST(concat(date_format(DATE_ADD(DAY,1,ts_begin_adjusted), 'yyyy-MM-dd'), ' 08:00:00') as timestamp),ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 0 AND hr_begin >= '19:00' AND sabado.weekday_name IN('Monday','Tuesday','Wednesday','Thursday','Friday') THEN DATE_DIFF(SECOND,ts_begin_adjusted,ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 0 AND hr_begin >= '12:00' AND sabado.weekday_name = 'Saturday' THEN DATE_DIFF(SECOND,ts_begin_adjusted,ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 1 AND hr_begin >= '19:00' AND hr_end >= '08:00' AND sabado.weekday_name IN('Monday','Tuesday','Wednesday','Thursday','Friday') THEN DATE_DIFF(SECOND,CAST(concat(date_format(DATE_ADD(DAY,1,ts_begin_adjusted), 'yyyy-MM-dd'), ' 08:00:00') as timestamp),ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 1 AND hr_begin >= '19:00' AND hr_end < '08:00' AND sabado.weekday_name IN('Monday','Tuesday','Wednesday','Thursday','Friday') THEN 899
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 1 AND (sabado.weekday_name = 'Sunday' OR sabado.is_brz_holiday = 'Holiday') THEN DATE_DIFF(SECOND,cast(date_format(DATE_ADD(DAY, 1, ts_begin_adjusted), 'yyyy-MM-dd 08:00:00') as TIMESTAMP),ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 1 AND (sabado.weekday_name = 'Sunday' OR sabado.is_brz_holiday = 'Holiday') AND hr_end < '08:00' THEN 899 --padrão 14min59seg
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 2 AND sabado.weekday_name = 'Saturday' AND sabado.is_brz_holiday = 'Holiday' THEN DATE_DIFF(SECOND,cast(date_format(DATE_ADD(DAY, 2, ts_begin_adjusted), 'yyyy-MM-dd 08:00:00') as TIMESTAMP),ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 2 AND hr_begin >= '12:00' AND hr_end >= '08:00' AND sabado.weekday_name = 'Saturday' THEN DATE_DIFF(SECOND,cast(date_format(DATE_ADD(DAY, 2, ts_begin_adjusted), 'yyyy-MM-dd 08:00:00') as TIMESTAMP),ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 2 AND hr_begin >= '12:00' AND hr_end < '08:00' AND sabado.weekday_name = 'Saturday' THEN 899 --padrão 14min59seg
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 2 AND sabado.weekday_name IN('Monday','Tuesday','Wednesday','Thursday') AND hr_begin >= '19:00' AND hr_end >= '08:00' AND holiday.is_brz_holiday = 'Holiday' THEN DATE_DIFF(SECOND,cast(date_format(DATE_ADD(DAY, 2, ts_begin_adjusted), 'yyyy-MM-dd 08:00:00') as TIMESTAMP),ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 2 AND sabado.weekday_name IN('Monday','Tuesday','Wednesday','Thursday') AND hr_begin >= '19:00' AND hr_end < '08:00' AND holiday.is_brz_holiday = 'Holiday' THEN DATE_DIFF(SECOND,cast(date_format(DATE_ADD(DAY, 2, ts_begin_adjusted), 'yyyy-MM-dd 08:00:00') as TIMESTAMP),ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) = 3 AND sabado.weekday_name IN('Friday') AND hr_begin >= '19:00' AND holiday.is_brz_holiday = 'Holiday' THEN DATE_DIFF(SECOND,cast(date_format(DATE_ADD(DAY, 3, ts_begin_adjusted), 'yyyy-MM-dd 08:00:00') as TIMESTAMP),ts_end)
        WHEN DATE_DIFF(DAY,DATE(ts_begin_adjusted),DATE(ts_end)) >= 3 AND sabado.weekday_name NOT IN('Friday') AND holiday.is_brz_holiday NOT IN ('Holiday') THEN DATE_DIFF(SECOND,ts_begin_adjusted,ts_end)
        WHEN ts_end IS NOT NULL THEN DATE_DIFF(SECOND,ts_begin_adjusted,ts_end)
    END AS sla_second,
    rank_table,
    is_last_register,
    dt_propose,
    ts_begin,
    ts_end,
    ts_operation
FROM
   cte_base_credito
LEFT JOIN
    dw_public.dim_date sabado
        ON sabado.date = date(ts_begin_adjusted)
LEFT JOIN
    dw_public.dim_date holiday
        ON holiday.date = date(date_add(DAY,1,ts_begin_adjusted))
