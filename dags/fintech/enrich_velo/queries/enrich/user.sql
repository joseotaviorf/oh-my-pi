WITH cte_union AS (
(
  SELECT
    uu.id AS id_user,
    NULL AS uuid_user,
    uu.name,
    uu.email,
    up.name AS user_role,
    uu.phone,
    TRUE AS is_legacy,
    uu.ts_inserted AS ts_created
  FROM
    datalake_velo_clean.users_users AS uu
  LEFT JOIN
    datalake_velo_clean.users_profile AS up
      ON up.id = uu.profile

)
UNION ALL
(
  WITH person AS (
      SELECT *
      FROM
          datalake_person_clean.person AS p
      QUALIFY
          ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY p.ts_updated DESC) = 1
  )
  SELECT
      ua.id AS id_user,
      ua.uuid_person AS uuid_user,
      p.person_name AS name,
      ua.email,
      pa.profile_name AS user_role,
      NULL AS phone,
      FALSE AS is_legacy,
      ua.ts_created
  FROM
      datalake_rental_guarantee_platform_clean.user_account AS ua
  LEFT JOIN
      datalake_rental_guarantee_platform_clean.company_user_account AS cua
      ON ua.id = cua.id_user_account
  LEFT JOIN
      datalake_rental_guarantee_platform_clean.profile_account AS pa
      ON cua.id_profile_account = pa.id
  LEFT JOIN
      person AS p
      ON ua.uuid_person = p.uuid_person
  WHERE
      ua.id >= 5000000


)
ORDER BY 1
)
SELECT
  id_user,
  uuid_user,
  name,
  phone,
  email,
  user_role,
  is_legacy,
  ts_created
FROM
    cte_union
