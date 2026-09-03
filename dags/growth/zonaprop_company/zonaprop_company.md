# Zonaprop Companies — MySQL CDC (Navent, RD-3334)

CDC ingestion of Zonaprop real-estate agency accounts, portal users, agency types and third-party interface mappings from the Navent MySQL portal. Supports B2B commercial and account analytics for the migration POC.

Schemas: `datalake_zonaprop_raw` (raw) / `datalake_zonaprop_clean` (clean).

## Tables

| Raw table | Clean table | PK | Z-order |
|---|---|---|---|
| `empresas` | `companies` | id_company | id_company |
| `usuariosempresas` | `company_users` | id_company_user | id_company |
| `tiposdeinmobiliaria` | `agency_types` | id_agency_type | id_agency_type |
| `interfaceempresas` | `interface_companies` | id_interface_company | id_company |
| `interfaceconfigurations` | `interface_configurations` | id_interface | id_interface |
| `interfaceconfigurationparameters` | `interface_configuration_parameters` | id_parameter | id_interface |

## Sibling DAGs

The Zonaprop CDC surface is split into five DAGs: `zonaprop_listing`, `zonaprop_company`, `zonaprop_commerce`, `zonaprop_catalog`, `zonaprop_demand`.

## Notes

- Shared column mapping across Navent portals; validated on Zonaprop.
- Depends on RD-3294 (Debezium + S3 sink) before first Forno run.
- `usuariosempresas.password` is excluded from clean (no credentials in clean layer).
