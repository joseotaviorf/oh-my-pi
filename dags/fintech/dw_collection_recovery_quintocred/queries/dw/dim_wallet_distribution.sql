WITH aux_team AS (
  SELECT
      creditor,
      id_contract,
      partner,
      dt_start_interval,
      dt_end_interval
  FROM
      datalake_recupera.changes_debts_distribution
  WHERE
      creditor = 'IQ QuintoCred'
      AND partner NOT IN ("GARANTIA","DPESQ","DFRAUDE","DBAIXAS","DVESPBX2","DVPRDIST","DCARGA","EXTERNO","DVNCOB")
),
aux_fill_range AS (
SELECT
    cdd.creditor,
    cdd.id_contract,
    cdd.partner,
    cdd.dt_start_interval,
    cdd.dt_end_interval,
    MAX(t.dt_start_interval) AS max_dt_start_interval
FROM
    datalake_recupera.changes_debts_distribution AS cdd
LEFT JOIN
    aux_team as t
      ON cdd.id_contract = t.id_contract
      AND cdd.dt_start_interval >= t.dt_start_interval
      AND (DATE_TRUNC("MONTH",cdd.dt_start_interval) = DATE_TRUNC("MONTH",t.dt_start_interval)
      OR DATE_TRUNC("MONTH",cdd.dt_start_interval) >= DATE_ADD(MONTH,-3,DATE_TRUNC("MONTH",t.dt_start_interval)))
WHERE cdd.creditor = 'IQ QuintoCred'
GROUP BY
    cdd.creditor,
    cdd.id_contract,
    cdd.partner,
    cdd.dt_start_interval,
    cdd.dt_end_interval
)

SELECT
    pp.document,
    fr.id_contract AS sk_contract,
    CASE
        WHEN t.partner IN ("DVAT360","DVACOINT","DVA91180","DVAT180M","DVAT6190","INTERNO BLOQUEADO","INTERNO VELO","COBINTQC") THEN "TIME INTERNO"
        WHEN t.partner IN ("PASCHOALOTTO") THEN "PASCH"
        ELSE t.partner
    END AS team,
    fr.dt_start_interval,
    fr.dt_end_interval
FROM
    aux_fill_range AS fr
JOIN aux_team AS t
    ON fr.id_contract = t.id_contract
    AND fr.max_dt_start_interval = t.dt_start_interval
LEFT JOIN dw_velo.fact_velo_propose AS p
    ON CAST(fr.id_contract AS INT) = p.sk_propose
LEFT JOIN dw_velo.dim_velo_propose_person AS pp
  ON p.sk_primary_person = pp.sk_person
WHERE
    fr.creditor = 'IQ QuintoCred'
QUALIFY ROW_NUMBER() OVER (PARTITION BY fr.dt_start_interval, pp.document ORDER BY
    CASE
        WHEN t.partner
            IN ("DVAT360","DVACOINT","DVA91180","DVAT180M","DVAT6190","INTERNO BLOQUEADO","INTERNO VELO","COBINTQC")
                THEN 1
        WHEN t.partner = 'IAF' THEN 2
        WHEN t.partner = 'PASCHOALOTTO' THEN 3
        WHEN t.partner = 'BRBOTS' THEN 4
        WHEN t.partner = 'DIGTECH' THEN 5
        ELSE 6
    END) = 1
