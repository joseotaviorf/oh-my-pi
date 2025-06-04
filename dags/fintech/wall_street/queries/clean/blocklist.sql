SELECT
    id,
    riskTypeId AS id_risk_type,
    blockedBy AS blocked_by,
    value,
    CAST(created_at AS TIMESTAMP) AS ts_created
FROM
    datalake_wall_street_raw.blocklist
