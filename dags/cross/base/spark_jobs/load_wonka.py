import argparse
import importlib
import logging

logger = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser(description="Run a Wonka pipeline.")
    parser.add_argument(
        "pipeline_runner",
        help="The path to the runner of the pipeline, e.g., "
        "dummy_feature_set.runner",
    )
    args = parser.parse_args()

    split_pipeline_runner = args.pipeline_runner.split(".")
    module_path = ".".join(split_pipeline_runner[:-1])
    pipeline_runner_instance_name = split_pipeline_runner[-1]

    module = importlib.import_module(module_path)
    pipeline_runner_instance = getattr(module, pipeline_runner_instance_name)

    pipeline_runner_instance.execute()


if __name__ == "__main__":
    main()
