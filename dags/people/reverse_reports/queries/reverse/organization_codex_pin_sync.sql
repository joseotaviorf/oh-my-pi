SELECT
    'MERGE' AS METADATA,
    'Organization' AS Organization,
    date_format(CURRENT_DATE(), 'yyyy/MM/dd') AS EffectiveStartDate,
    '4712/12/31' AS EffectiveEndDate,
    pin_organization_name AS Name,
    'DEPARTMENT' AS ClassificationCode,
    'DEPARTMENT' AS ClassificationName,
    'Global Data Elements' AS `FLEX:PER_ORGANIZATION_UNIT_DFF`,
    TRIM(cost_center_code) AS `codigo(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    codex_business AS `business(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    codex_product AS `product(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    codex_vertical AS `vertical(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    codex_brand AS `brand(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    codex_structure AS `structure(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    codex_team AS `team(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    COALESCE(codex_chapter, '-') AS `chapter(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    COALESCE(codex_line, '-') AS `line(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    COALESCE(codex_owner_l1_full_name, '-') AS `l1Cc(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    COALESCE(codex_owner_l2_full_name, '-') AS `l2Cc(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    COALESCE(codex_owner_l3_full_name, '-') AS `l3Cc(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    COALESCE(codex_headcount_type, '-') AS `headcountType(PER_ORGANIZATION_UNIT_DFF=Global Data Elements)`,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    datalake_people.codex_pin_sync_drift
WHERE
    is_any_drift
ORDER BY
    Name
