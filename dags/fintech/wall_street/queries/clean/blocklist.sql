SELECT
    id,
    riskTypeId AS id_risk_type,
    blockedBy AS blocked_by,
    value,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_wall_street_raw.blocklist
