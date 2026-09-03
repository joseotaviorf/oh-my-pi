# Zonaprop Catalog — MySQL CDC (Navent, RD-3334)

CDC ingestion of Zonaprop geographic, property-type and currency reference catalogs from the Navent MySQL portal. Shared dimension tables for listings, companies and commerce facts in the migration POC.

Schemas: `datalake_zonaprop_raw` (raw) / `datalake_zonaprop_clean` (clean).

## Tables

| Raw table | Clean table | PK | Z-order |
|---|---|---|---|
| `paises` | `countries` | id_country | id_country |
| `provincias` | `states` | id_state | id_state |
| `ciudades` | `cities` | id_city | id_city |
| `zonasciudad` | `city_zones` | id_city_zone | id_city |
| `subzonasciudad` | `city_subzones` | id_city_subzone | id_city |
| `geolocalizaciones` | `geolocations` | id_geolocation | id_geolocation |
| `tiposdepropiedad` | `property_types` | id_property_type | id_property_type |
| `subtiposdepropiedad` | `property_subtypes` | id_property_subtype | id_property_type |
| `tiposdeoperacion` | `operation_types` | id_operation_type | id_operation_type |
| `etapasdedesarrollo` | `development_stages` | id_development_stage | id_development_stage |
| `monedas` | `currencies` | id_currency | id_currency |

## Sibling DAGs

The Zonaprop CDC surface is split into five DAGs: `zonaprop_listing`, `zonaprop_company`, `zonaprop_commerce`, `zonaprop_catalog`, `zonaprop_demand`.

## Notes

- Shared column mapping across Navent portals; validated on Zonaprop.
- Depends on RD-3294 (Debezium + S3 sink) before first Forno run.
- `usuariosempresas.password` is excluded from clean (no credentials in clean layer).
