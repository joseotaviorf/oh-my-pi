WITH starting_value AS (
    SELECT
        COALESCE(MAX(sk_file), 0) AS max_sk_file
    FROM
        datalake_rede_supply.file_sks
)
SELECT
    COALESCE(
        sk_file, -- Keep the sk_file if it is already defined, so it is durable
        sv.max_sk_file + MONOTONICALLY_INCREASING_ID() + 1 -- if not, use a number after the previous maximum value
    ) AS sk_file,
    f.id AS id_file -- Natural key
FROM
    datalake_brokers_supply_processor.file AS f,
    starting_value AS sv
LEFT JOIN 
    datalake_rede_supply.file_sks AS fs
        ON f.id = fs.id_file