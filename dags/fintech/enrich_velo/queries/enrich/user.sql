SELECT
  uu.id AS id_user,
  uu.name,
  uu.email,
  up.name AS user_role,
  uu.phone,
  uu.ts_inserted AS ts_created
FROM
  datalake_velo_clean.users_users AS uu
LEFT JOIN
  datalake_velo_clean.users_profile AS up
    ON up.id = uu.profile
