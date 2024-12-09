SELECT
    1 AS sk_visit_fup,
    'EntradaNaoAutorizada' AS visit_fup,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_visit_fup,
    'ImovelAlugado' AS visit_fup,
    NOW() AS ts_load
UNION ALL
SELECT
    3 AS sk_visit_fup,
    'NaoCompareceu' AS visit_fup,
    NOW() AS ts_load
UNION ALL
SELECT
    4 AS sk_visit_fup,
    'NaoGostou' AS visit_fup,
    NOW() AS ts_load
UNION ALL
SELECT
    5 AS sk_visit_fup,
    'Talvez' AS visit_fup,
    NOW() AS ts_load
UNION ALL
SELECT
    6 AS sk_visit_fup,
    'VaiNegociar' AS visit_fup,
    NOW() AS ts_load
UNION ALL
SELECT
    7 AS sk_visit_fup,
    'VisitouSozinho' AS visit_fup,
    NOW() AS ts_load
