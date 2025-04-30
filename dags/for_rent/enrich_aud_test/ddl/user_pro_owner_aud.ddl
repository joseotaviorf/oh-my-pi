CREATE OR REPLACE TABLE datalake_aud_test.user_pro_owner_aud
PARTITIONED BY (year, month, day)
LOCATION "s3://5a-datalake-prod/enrich/aud_test/user_pro_owner_aud/" AS
SELECT
  BIGINT(aud.id) AS id,
  BIGINT(aud.id_user) AS id_user,
  BIGINT(aud.id_account_manager) AS id_account_manager,
  aud.is_active,
  aud.rev_type,
  ure.ts_revision,
  YEAR(ure.ts_revision) AS year,
  MONTH(ure.ts_revision) AS month,
  DAY(ure.ts_revision) AS day
FROM
  datalake_ebdb_clean.user_pro_owner_aud as aud
JOIN
  datalake_ebdb_user.user_revision_entity as ure
    ON aud.rev = ure.id
WHERE
  DATE(ts_revision) <= "2024-12-31"
