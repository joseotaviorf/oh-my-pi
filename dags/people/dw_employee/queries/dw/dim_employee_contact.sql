WITH
  hr_system_workers AS (
    SELECT
      id_person,
      emails,
      addresses,
      phones
    FROM
      datalake_hr_system_clean.workers 
    QUALIFY 2 = DENSE_RANK() OVER (
        PARTITION BY
          id_person
        ORDER BY
          dt_effective
      )
  ),
  emails_step1 AS (
    SELECT
      id_person,
      EXPLODE (emails) emails
    FROM
      hr_system_workers
  ),
  emails AS (
    SELECT
      id_person,
      emails['EmailAddressId'] AS id_email_address,
      emails['EmailType'] AS email_type,
      emails['EmailAddress'] AS email_address,
      emails['PrimaryFlag'] AS primary_flag,
      TO_TIMESTAMP(
        SUBSTR(REPLACE(emails['LastUpdateDate'], 'T', ' '), 0, 19),
        'yyyy-MM-dd HH:mm:ss'
      ) AS ts_last_update
    FROM
      emails_step1
    WHERE
      emails['ToDate'] IS NULL
      OR emails['ToDate'] = '4712-12-31' 
    QUALIFY emails['LastUpdateDate'] = MAX(emails['LastUpdateDate']) OVER (
        PARTITION BY
          id_person,
          emails['EmailType']
      )
  ),
  addresses_step1 AS (
    SELECT
      id_person,
      EXPLODE (addresses) addresses
    FROM
      hr_system_workers
  ),
  addresses AS (
    SELECT
      id_person,
      addresses['AddressId'] AS id_address,
      addresses['AddlAddressAttribute3'] AS addl_address_attribute_3,
      addresses['AddressLine1'] AS address_line_1,
      addresses['AddressLine2'] AS address_line_2,
      addresses['AddressLine3'] AS address_line_3,
      addresses['AddressLine4'] AS address_line_4,
      addresses['PostalCode'] AS postal_code,
      addresses['TownOrCity'] AS town_or_city,
      addresses['Region2'] AS region_2,
      addresses['Country'] AS country,
      DATE(addresses['EffectiveStartDate']) AS dt_effective_start
    FROM
      addresses_step1
    WHERE
      addresses['PrimaryFlag'] = 'true'
  ),
  phones_step1 AS (
    SELECT
      id_person,
      EXPLODE (phones) AS phones
    FROM
      hr_system_workers
  ),
  phones AS (
    SELECT
      id_person,
      phones['PhoneId'] AS id_phone,
      phones['CountryCodeNumber'] AS country_code_number,
      phones['AreaCode'] AS area_code,
      phones['PhoneNumber'] AS phone_number,
      TO_TIMESTAMP(
        SUBSTR(REPLACE(phones['LastUpdateDate'], 'T', ' '), 0, 19),
        'yyyy-MM-dd HH:mm:ss'
      ) AS ts_last_update
    FROM
      phones_step1
    WHERE
      phones['PrimaryFlag'] = 'true'
  )
SELECT
  workers.id_person AS sk_employee,
  ew.email_address AS work_email,
  eh.email_address AS personal_email,
  phones.country_code_number,
  phones.area_code,
  phones.phone_number,
  CONCAT(addresses.addl_address_attribute_3, ' ', addresses.address_line_1) AS address,
  addresses.address_line_2 AS address_number,
  addresses.address_line_3 AS address_complement,
  addresses.address_line_4 AS address_district,
  addresses.postal_code AS address_zip_code,
  addresses.town_or_city AS address_city,
  addresses.region_2 AS address_state,
  addresses.country AS address_country,
  GREATEST (
    addresses.dt_effective_start,
    DATE(ew.ts_last_update),
    DATE(eh.ts_last_update),
    DATE(phones.ts_last_update)
  ) AS ts_last_update,
  NOW() AS ts_load
FROM
  hr_system_workers AS workers
LEFT JOIN 
  emails AS ew 
    ON workers.id_person = ew.id_person
      AND ew.email_type = 'W1'
LEFT JOIN 
  emails AS eh 
    ON workers.id_person = eh.id_person
      AND eh.email_type = 'H1'
LEFT JOIN 
  addresses 
    ON workers.id_person = addresses.id_person
LEFT JOIN 
  phones 
    ON workers.id_person = phones.id_person
WHERE
  GREATEST (
    addresses.dt_effective_start,
    DATE(ew.ts_last_update),
    DATE(eh.ts_last_update),
    DATE(phones.ts_last_update)
  ) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')