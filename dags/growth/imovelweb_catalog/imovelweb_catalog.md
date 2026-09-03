# Imovelweb Catalog — Imovelweb CDC

CDC ingestion slice for **geo and property reference catalogs (countries through currencies) shared across listings and companies** from Imovelweb's Navent MySQL database ([RD-3333](https://quintoandar.atlassian.net/browse/RD-3333), parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

Schemas: `datalake_imovelweb_raw` (raw) and `datalake_imovelweb_clean` (clean). Column mapping is shared across Navent portals (Zonaprop/Imovelweb/RealEstate); validate against Imovelweb live schema before the first Forno run.

## Tables

| Clean table | Raw table | Grain / PK | Z-ORDER |
|---|---|---|---|
| `countries` | `paises` | one row per country (PK `id_country`) | id_country |
| `states` | `provincias` | one row per state (PK `id_state`) | id_state |
| `cities` | `ciudades` | one row per city (PK `id_city`) | id_city |
| `city_zones` | `zonasciudad` | one row per city zone (PK `id_city_zone`) | id_city |
| `city_subzones` | `subzonasciudad` | one row per city sub-zone (PK `id_city_subzone`) | id_city |
| `geolocations` | `geolocalizaciones` | one row per geolocation (PK `id_geolocation`) | id_geolocation |
| `property_types` | `tiposdepropiedad` | operational PK `id_property_type` (source has no MySQL PRIMARY KEY yet; uniqueness assumed until Navent adds it) | id_property_type |
| `property_subtypes` | `subtiposdepropiedad` | one row per property subtype (PK `id_property_subtype`) | id_property_type |
| `operation_types` | `tiposdeoperacion` | one row per operation type (PK `id_operation_type`) | id_operation_type |
| `development_stages` | `etapasdedesarrollo` | one row per development stage (PK `id_development_stage`) | id_development_stage |
| `currencies` | `monedas` | one row per currency (PK `id_currency`) | id_currency |

## Notes

- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for Forno/prod runs.
- `company_users.password` is excluded from clean; other PII columns remain without `table_privileges` in this POC.
- `empresas.falta` → `dt_missing` and `usuariosempresas.falta` → `ts_missing`: Spanish column semantics not yet confirmed with domain owner.
- `listing_rankings`: declaration PK is `id_listing`; logical grain may be composite — validate against source before tightening DQ.
- `property_types` (`tiposdepropiedad`): Imovelweb production has **no PRIMARY KEY** — only `KEY idtipodepropiedad` (`NON_UNIQUE=1`, `DEFAULT 0`). The DAG uses `id_property_type` as the **operational CDC merge key**, matching Zonaprop/RealEstate. DQ uniqueness is **Warning** until Navent adds `PRIMARY KEY (idtipodepropiedad)` in `navplat_realestate_imovelweb`. SageMaker 2026-09-02: 17 rows, 0 duplicate ids.
