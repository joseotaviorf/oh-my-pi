SELECT
    CAST(cep AS STRING) AS zipcode, 
    CAST(cidade_nome AS STRING) AS city, 
    CAST(bairro AS STRING) AS neighborhood, 
    CAST(logradouro AS STRING) AS address, 
    CAST(latitude AS DOUBLE) AS lat, 
    CAST(longitude AS DOUBLE) AS lng 
FROM
    datalake_gsheets_raw.zipcodes_sp
