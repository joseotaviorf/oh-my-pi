"""Registry of AI enrichment products enabled by the DAG."""

from importlib import resources

import yaml

from dags.people.enrich_people_ai.spark_jobs.lib.ai_enrichment import (
    AIProduct,
    AIProductConfig,
)
from dags.people.enrich_people_ai.spark_jobs.products import teva


def _load_product_configs() -> dict:
    """Load operational settings bundled with the Spark job package.

    Returns:
        Mapping from product keys to the raw YAML configuration blocks.

    Raises:
        OSError: If the packaged configuration cannot be opened.
        yaml.YAMLError: If the configuration is not valid YAML.
    """
    config_path = resources.files(__package__).joinpath("ai_products.yml")
    with config_path.open("r", encoding="utf-8") as config_file:
        config = yaml.safe_load(config_file) or {}
    return config.get("products") or {}


def _build_product_config(product_key: str) -> AIProductConfig:
    """Validate and convert one raw YAML block into typed settings.

    Args:
        product_key: Product key whose configuration should be loaded.

    Returns:
        Typed operational settings for the product.

    Raises:
        ValueError: If the product is missing or has an invalid configuration.
    """
    try:
        raw_config = _load_product_configs()[product_key]
        request_config = raw_config["request"]
        return AIProductConfig(
            model=raw_config["model"],
            max_calls_per_run=int(raw_config["max_calls_per_run"]),
            max_concurrency=int(raw_config.get("max_concurrency", 1)),
            prompt_version=str(raw_config["prompt_version"]),
            processing_mode=str(raw_config.get("processing_mode", "new_only")),
            temperature=float(request_config["temperature"]),
            max_tokens=int(request_config["max_tokens"]),
            timeout_seconds=int(request_config["timeout_seconds"]),
            max_retries=int(request_config["max_retries"]),
        )
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError(
            f"Invalid AI product configuration for '{product_key}'."
        ) from exc


PRODUCT_DEFINITIONS = {
    "teva": {
        "input_database": teva.INPUT_DATABASE,
        "input_table": teva.INPUT_TABLE,
        "merge_on": teva.MERGE_ON,
        "build_prompt": teva.build_prompt,
        "parse_response": teva.parse_response,
        "build_output_schema": teva.build_output_schema,
        "classification_column": "ai_executive_summary",
    }
}


def get_product(product_key: str) -> AIProduct:
    """Build and return a configured product adapter.

    Args:
        product_key: Key selected by ``--product`` in the DAG declaration.

    Returns:
        Product behavior combined with its YAML operational configuration.

    Raises:
        ValueError: If the key is not registered or its configuration is invalid.
    """
    try:
        definition = PRODUCT_DEFINITIONS[product_key]
        return AIProduct(
            key=product_key,
            config=_build_product_config(product_key),
            **definition,
        )
    except KeyError as exc:
        available = ", ".join(sorted(PRODUCT_DEFINITIONS))
        raise ValueError(
            f"Unknown AI product '{product_key}'. Available products: {available}."
        ) from exc
