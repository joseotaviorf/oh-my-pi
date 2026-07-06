# Owner Properties Listing — database reference

PostgreSQL service **owner-properties-listing** (`applications/owner-properties-listing` in backend-services).
CDC landing: `s3://5a-datalake-incoming-{env}/owner-properties-listing/`.

Lake schemas:
- **Raw:** `datalake_owner_properties_listing_raw` — mirrors OLTP table names (`tb_*`, `revinfo`).
- **Clean:** `datalake_owner_properties_listing_clean` — snake_case names **without** the `tb_` prefix; columns normalized (`id_*`, `ts_*`, `mod_*` on `_aud`).

## Raw → clean table mapping

| Raw (OLTP / `datalake_owner_properties_listing_raw`) | Clean (`datalake_owner_properties_listing_clean`) |
|---|---|
| `revinfo` | `rev_info` |
| `tb_property` | `property` |
| `tb_property_aud` | `property_aud` |
| `tb_ownership` | `ownership` |
| `tb_ownership_aud` | `ownership_aud` |
| `tb_listing_status` | `listing_status` |
| `tb_listing_score` | `listing_score` |
| `tb_listing_score_aud` | `listing_score_aud` |
| `tb_listing_relationship` | `listing_relationship` |
| `tb_listing_relationship_aud` | `listing_relationship_aud` |
| `tb_related_as` | `related_as` |
| `tb_related_as_aud` | `related_as_aud` |
| `tb_source_type` | `source_type` |
| `tb_source_type_aud` | `source_type_aud` |
| `tb_user` | `listing_user` |
| `tb_user_type` | `user_type` |
| `tb_daily_visit_property` | `daily_visit_property` |
| `tb_status_offer` | `status_offer` |
| `tb_accepted_rent_offer` | `accepted_rent_offer` |
| `tb_accepted_rent_offer_aud` | `accepted_rent_offer_aud` |

`tb_user` maps to **`listing_user`** in clean to avoid ambiguity with platform-wide `user` entities (`dim_user`, Person service).

## Naming conventions (clean layer)

- **FK columns:** `*_id` → `id_*` (e.g. `property_id` → `id_property`).
- **Timestamps:** `created_at` / `updated_at` → `ts_created` / `ts_updated`.
- **Dates:** `scheduled_to` → `dt_scheduled`.
- **Booleans:** `active` → `is_active` (when present).
- **Envers audit:** `revend` → `rev_end`, `revtype` → `rev_type`, `*_mod` → `mod_*`.
- **Reserved words:** OLTP `type` → descriptive alias (`listing_status_type`, `related_as_type`, …).

## Datalake outputs

| Layer | Schema | Tables |
|---|---|---|
| Raw | `datalake_owner_properties_listing_raw` | 20 CDC tables (OLTP names) |
| Clean | `datalake_owner_properties_listing_clean` | 20 normalized tables (see `queries/clean/`) |
