SELECT
    cc.id AS id_crawler,
    CONCAT("https://app.legaut.com/units/", cc.id_unit) AS link_imovel_analise,
    CONCAT("https://imoveis.legaut.com/building/", msu.id_operation) AS link_imovel_imoveis,
    cc.type AS crawler_type,
    mss.name AS crawler_state,
    msc.name AS crawler_city,
    msp.name AS project,
    cct.label AS crawler_type_label,
    cc.status AS crawler_status,
    msd.file_name AS document,
    msu.ts_created AS ts_operation_created_at,
    cc.ts_run_start AS ts_crawler_run_start,
    cc.ts_run_end AS ts_crawler_run_end
FROM
  datalake_legaut_clean.crawlers_crawler AS cc
INNER JOIN
  datalake_legaut_clean.meusite_unit AS msu
    ON cc.id_unit = msu.id
LEFT OUTER JOIN
  datalake_legaut_clean.crawlers_crawlergroup AS ccg
    ON cc.id_crawler_group = ccg.id
LEFT OUTER JOIN
  datalake_legaut_clean.meusite_document AS msd
    ON cc.id_document = msd.id
LEFT OUTER JOIN
  datalake_legaut_clean.meusite_city AS msc
    ON ccg.id_city = msc.id
LEFT OUTER JOIN
  datalake_legaut_clean.meusite_state AS mss
    ON msc.id_state = mss.id
LEFT OUTER JOIN
  datalake_legaut_clean.meusite_project AS msp
    ON msu.id_project = msp.id
LEFT OUTER JOIN
  datalake_legaut_clean.crawlers_crawlertype AS cct
    ON cct.value = cc.type
