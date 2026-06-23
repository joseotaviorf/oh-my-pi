"""Resolve Wonka pipeline targets to importable modules without dynamic path assembly."""

import importlib
import inspect
import pkgutil
import re
from functools import lru_cache
from typing import Dict

_VALID_PIPELINE_PACKAGE = re.compile(r"^[a-z][a-z0-9_]*$")


def validate_pipeline_target(pipeline_target: str) -> str:
    """Reject pipeline targets that are not safe Python package names (CWE-94).

    Values come from Airflow (the DAG name), not end users. Only snake_case
    top-level package names are accepted.
    """
    if not pipeline_target:
        raise ValueError("pipeline_target must not be empty")

    if not _VALID_PIPELINE_PACKAGE.match(pipeline_target):
        raise ValueError(
            f"Invalid pipeline package '{pipeline_target}': must match [a-z][a-z0-9_]*"
        )

    return pipeline_target


def _find_pipeline_class(module):
    feature_set_pipeline_module = importlib.import_module(
        "butterfree.pipelines.feature_set_pipeline"
    )
    FeatureSetPipeline = feature_set_pipeline_module.FeatureSetPipeline

    for _, candidate in inspect.getmembers(module, inspect.isclass):
        if (
            issubclass(candidate, FeatureSetPipeline)
            and candidate is not FeatureSetPipeline
        ):
            return candidate

    raise ValueError(
        f"No FeatureSetPipeline subclass found in module '{module.__name__}'"
    )


@lru_cache(maxsize=1)
def _package_module_registry() -> Dict[str, str]:
    """Map Wonka package names to module paths discovered from sys.path."""
    registry: Dict[str, str] = {}
    for module_info in pkgutil.iter_modules():
        package_name = module_info.name
        if not _VALID_PIPELINE_PACKAGE.match(package_name):
            continue
        registry[package_name] = f"{package_name}.{package_name}"
    return registry


def build_wonka_runner(pipeline_target: str) -> object:
    """Build a Wonka runner from a validated pipeline package name."""
    validated_target = validate_pipeline_target(pipeline_target)

    wonka_runner_module = importlib.import_module(
        "wonka_core.butterfree_customs.wonka_runner"
    )
    WonkaRunner = wonka_runner_module.WonkaRunner

    package_registry = _package_module_registry()
    if validated_target not in package_registry:
        raise ValueError(
            f"Unknown Wonka pipeline package '{validated_target}'. "
            "No matching top-level package was found on sys.path."
        )
    module_path = package_registry[validated_target]
    module = importlib.import_module(module_path)
    pipeline_class = _find_pipeline_class(module)
    return WonkaRunner(pipeline_class())
