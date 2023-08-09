/*
  Due to complexity to identify the historical users to a current user, 
  we decided to create a notebook to create this historical.
  If one day this table is deleted and should be recreated, 
  we need to run the 3 first cmd in this notebook before running the tasks of this table. 
  https://dbc-931ee6e0-6803.cloud.databricks.com/?o=4531937035440038#notebook/3238664573531777/command/547319918007525

  To run the notebook we should install the graphframes lib to the cluster.
  The link to it is above the import of it.
*/

WITH users_merged AS(
  SELECT
    u.id AS id_user,
    um.id_winner_account,
    um.id_loser_account
  FROM 
    datalake_ebdb_clean.user AS u
  JOIN
    datalake_ebdb_clean.user_merge AS um
      ON u.id = um.id_winner_account
      AND um.status = 'MERGED'
  WHERE
    DATE(um.ts_created) = DATE(DATE_ADD(NOW(), -1))
)

SELECT
  COALESCE(um.id_winner_account, umf.id_user) AS id_user,
  u.country_code,
  IF(um.id_loser_account IS NOT NULL,
    IF(
      ARRAY_CONTAINS(umf.predecessor_user_list, um.id_loser_account), 
      umf.predecessor_user_list, 
      ARRAY_APPEND(COALESCE(umf.predecessor_user_list, ARRAY()), um.id_loser_account)
    ),
    umf.predecessor_user_list
  ) AS predecessor_user_list
FROM
  datalake_ebdb_user.user_merge AS umf
LEFT JOIN
  users_merged AS um
    ON umf.id_user = um.id_loser_account
LEFT JOIN
  datalake_ebdb_country.user AS u
    ON COALESCE(um.id_winner_account, umf.id_user) = u.id_user