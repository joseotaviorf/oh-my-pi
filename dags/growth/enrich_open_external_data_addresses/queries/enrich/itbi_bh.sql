WITH addresses AS (
    SELECT 
      /*
      The functions below are used to extract each part of the address from the address column of the Belo Horizonte city hall.

      All address information is separated by a hyphen (except the street number, which comes after the street). And depending on how many hyphens we have in the string, we know how much information is in the string.

      E.g.: RUA DOS GOITACAZES 152 - APT 604 - CENTRO - 30190-050 - BELO HORIZONTE - MG

      Being a more standard string, we have as:

      Street: RUA DOS GOITACAZES 152 
      Number: 152
      Complement: APT 604
      Neighborhood: CENTRO
      Zip Code: 30190-050
      City: BELO HORIZONTE
      State: MG
      */
      IF(
        SIZE(SPLIT(address, ' - ')) IN (4, 5, 6, 7),
        IF(
          LEFT(REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],1) IN ('0','1','2','3','4','5','6','7','8','9'),
          ARRAY_JOIN(SLICE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '), 1, SIZE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' ')) - 1), ' '),
          ELEMENT_AT(SPLIT(address, ' - '), 1)
        ),
        'N/A'
      ) AS address,
      IF(
        SIZE(SPLIT(address, ' - ')) IN (5, 6, 7) AND LEFT(REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],1) IN ('0','1','2','3','4','5','6','7','8','9'),
        REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],
        'N/A'
      ) AS number,
      CASE
        WHEN SIZE(SPLIT(address, ' - ')) = 6 THEN ELEMENT_AT(SPLIT(address, ' - '), 2)
        WHEN SIZE(SPLIT(address, ' - ')) = 7
        THEN ARRAY_JOIN(slice(SPLIT(address, ' - '), 2, 2), ' - ')
      END AS complement,
      IF(
        SIZE(SPLIT(address, ' - ')) IN (4, 5, 6, 7), 
        ELEMENT_AT(SPLIT(address, ' - '), SIZE(SPLIT(address, ' - ')) - 2), 
        'N/A'
      ) AS zipcode,
      IF(
        SIZE(SPLIT(address, ' - ')) IN (5, 6, 7), 
        ELEMENT_AT(SPLIT(address, ' - '), SIZE(SPLIT(address, ' - ')) - 3),
        'N/A'
      ) AS neighborhood,
      'Belo Horizonte' AS city
    FROM
        datalake_itbi_clean.itbi_bh
    WHERE
      occupation_description = 'RESIDENCIAL'
)
SELECT DISTINCT
  MD5(CONCAT(address, number, city)) AS id_address,
  address,
  number,
  neighborhood,
  zipcode,
  city
FROM
  addresses