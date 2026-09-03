# RealEstate Catalog — MySQL CDC (Navent)

CDC slice of the RealEstate Navent MySQL database for the **catalog** domain. Parent initiative: [RD-3335](https://quintoandar.atlassian.net/browse/RD-3335) (Navent → QuintoAndar migration POC, parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

**Schedule:** `0 8,12,21 * * *` (3× daily at minute 0 UTC).
**Schemas:** `datalake_realestate_raw` / `datalake_realestate_clean` (shared across all RealEstate CDC DAGs).
**Secret:** `REALESTATE_DB`

## Tables

| Raw table | Clean table | Grain / PK | Z-order |
|---|---|---|---|
| `ciudades` | `cities` | id_city | id_city |
| `etapasdedesarrollo` | `development_stages` | id_development_stage | id_development_stage |
| `geolocalizaciones` | `geolocations` | id_geolocation | id_geolocation |
| `monedas` | `currencies` | id_currency | id_currency |
| `paises` | `countries` | id_country | id_country |
| `provincias` | `states` | id_state | id_state |
| `subtiposdepropiedad` | `property_subtypes` | id_property_subtype | id_property_type |
| `subzonasciudad` | `city_subzones` | id_city_subzone | id_city |
| `tiposdeoperacion` | `operation_types` | id_operation_type | id_operation_type |
| `tiposdepropiedad` | `property_types` | id_property_type | id_property_type |
| `zonasciudad` | `city_zones` | id_city_zone | id_city |

## Notes

- No date partitions on any table; rely on Z-order keys documented in metadata.
- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for raw data availability.
- Column mapping shared with Zonaprop/Imovelweb Navent portals; validated against Zonaprop mapping spreadsheet.
