# Imovelweb Company — Imovelweb CDC

CDC ingestion slice for **real-estate agencies (companies), agency users, agency types, and third-party interface bindings** from Imovelweb's Navent MySQL database ([RD-3333](https://quintoandar.atlassian.net/browse/RD-3333), parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

Schemas: `datalake_imovelweb_raw` (raw) and `datalake_imovelweb_clean` (clean). Column mapping is shared across Navent portals (Zonaprop/Imovelweb/RealEstate); validate against Imovelweb live schema before the first Forno run.

## Tables

| Clean table | Raw table | Grain / PK | Z-ORDER |
|---|---|---|---|
| `companies` | `empresas` | one row per agency (PK `id_company`) | id_company |
| `company_users` | `usuariosempresas` | one row per company user (PK `id_company_user`; `password` excluded from clean) | id_company |
| `agency_types` | `tiposdeinmobiliaria` | one row per agency type (PK `id_agency_type`) | id_agency_type |
| `interface_companies` | `interfaceempresas` | one row per interface-company link (PK `id_interface_company`) | id_company |
| `interface_configurations` | `interfaceconfigurations` | one row per interface integration (PK `id_interface`) | id_interface |
| `interface_configuration_parameters` | `interfaceconfigurationparameters` | one row per configuration parameter (PK `id_parameter`) | id_interface |

## Notes

- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for Forno/prod runs.
- `company_users.password` is excluded from clean; other PII columns remain without `table_privileges` in this POC.
- `empresas.falta` → `dt_missing` and `usuariosempresas.falta` → `ts_missing`: Spanish column semantics not yet confirmed with domain owner.
- `listing_rankings`: declaration PK is `id_listing`; logical grain may be composite — validate against source before tightening DQ.
