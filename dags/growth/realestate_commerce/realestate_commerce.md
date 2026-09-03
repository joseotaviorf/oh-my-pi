# RealEstate Commerce — MySQL CDC (Navent)

CDC slice of the RealEstate Navent MySQL database for the **commerce** domain. Parent initiative: [RD-3335](https://quintoandar.atlassian.net/browse/RD-3335) (Navent → QuintoAndar migration POC, parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

**Schedule:** `0 8,12,21 * * *` (3× daily at minute 0 UTC).
**Schemas:** `datalake_realestate_raw` / `datalake_realestate_clean` (shared across all RealEstate CDC DAGs).
**Secret:** `REALESTATE_DB`

## Tables

| Raw table | Clean table | Grain / PK | Z-order |
|---|---|---|---|
| `itemspedido` | `order_items` | id_order_item | id_order |
| `lineasdeproducto` | `product_lines` | id_product_line | id_product_line |
| `pedidos` | `orders` | id_order | id_order |
| `planesdepublicacion` | `publication_plans` | id_publication_plan | id_publication_plan |
| `planesporproductoporpais` | `plans_by_product_by_country` | id_publication_plan, id_product, id_country | id_publication_plan, id_product, id_country |
| `productos` | `products` | id_product | id_product |

## Notes

- No date partitions on any table; rely on Z-order keys documented in metadata.
- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for raw data availability.
- Column mapping shared with Zonaprop/Imovelweb Navent portals; validated against Zonaprop mapping spreadsheet.
