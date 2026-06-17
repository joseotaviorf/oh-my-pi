#!/usr/bin/env bash
set -euo pipefail


#####################################################################################
# This script is used to install different types of pex packages on Databricks.
# PEX files that are installed should be built from within the QuintoML ecosystem.
#
# Requirements:
#   - PACKAGE_PATH needs to be set to a valid S3 path
#   - For Databricks, the package should contain a requirements.txt
#	  file with all the dependencies and a PEX file built with tools (i.e. include_tools=True)
#   - For EMR, the package should contain a PEX file built with
#     tools and requirements (i.e. include_tools=True and include_requirements=True)
#
#####################################################################################

setup_databricks() {
	# This function expects the PACKAGE_PATH to be passed as an environment variable.
	#
	# For Databricks, it is expected that the content of the PACKAGE_PATH in S3 is the following:
	#
	# s3://.../SOME_COMMIT_HASH/			# Will mirror the local ./artifacts directory
	# ├── requirements.txt
	# └── main.pex

	pip install pip==24.0
	pip install awscli

	mkdir -p artifacts

	echo "Downloading artifacts from $PACKAGE_PATH"
	aws s3 sync "$PACKAGE_PATH" ./artifacts

	# Install 3rdparty dependencies
	/databricks/python/bin/pip install -r artifacts/requirements.txt # Runs on the Databricks cluster

	# Create virtual environment with internal packages
	chmod +x artifacts/*.pex
	export PEX_TOOLS=1

	if ! python ./artifacts/*.pex venv ./venv; then
		echo "Failed to create virtual environment"
		exit 1
	fi

	# Extract PYTHON_VERSION from venv path on linux
	PYTHON_VERSION=$(./venv/bin/python -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")

	# Move internal packages from virtual environment to Databricks Python environment
	rsync -a -v "./venv/lib/python${PYTHON_VERSION}/site-packages/" "/databricks/python/lib/python${PYTHON_VERSION}/site-packages/"
}

_ensure_emr_aws_cli() {
	if aws --version &>/dev/null 2>&1; then
		return 0
	fi
	echo "EMR: repairing AWS CLI python-dateutil in /usr/lib/python3.9/site-packages..."
	sudo python3 -m pip install --no-cache-dir --upgrade --force-reinstall \
		--target=/usr/lib/python3.9/site-packages \
		'python-dateutil==2.9.0' 'six>=1.5'
	aws --version &>/dev/null 2>&1 || {
		echo "ERROR: AWS CLI unavailable after dateutil repair." >&2
		exit 1
	}
}

setup_emr() {
	# This function expects the PACKAGE_PATH to be passed as an argument.
	#
	# For EMR, it is expected that the content of the PACKAGE_PATH in S3 is the following:
	#
	# s3://.../SOME_COMMIT_HASH/			# Will mirror the local ./artifacts directory
	# └── main.pex

	local python_version=3.11
	local python_bin artifacts_dir=/home/hadoop/artifacts venv_dir=/home/hadoop/venv pex_file

	python_bin=$(command -v "python${python_version}") || {
		echo "ERROR: python${python_version} is not pre-installed on this EMR release." >&2
		exit 1
	}

	mkdir -p "$artifacts_dir"
	echo "Downloading artifacts from $PACKAGE_PATH"
	_ensure_emr_aws_cli
	aws s3 sync "$PACKAGE_PATH" "$artifacts_dir"

	chmod +x "$artifacts_dir"/*.pex
	export PEX_TOOLS=1

	pex_file=$(find "$artifacts_dir" -maxdepth 1 -name "*.pex" | head -n 1)
	[[ -n "$pex_file" && -e "$pex_file" ]] || {
		echo "ERROR: No PEX file found under $artifacts_dir" >&2
		exit 1
	}

	echo "Using PEX: $pex_file ($("$python_bin" --version 2>&1))"
	PEX_TOOLS=1 "$python_bin" "$pex_file" venv "$venv_dir" || {
		echo "Failed to create virtual environment" >&2
		exit 1
	}

	# For Wonka DAGs, this path for the PEX-based Python interpreter needs to be the same as the one
	# set in `packages/bietlejuice-core/src/bietlejuice/base/airflow/task_creators/load_wonka_task_creator.py`.
	chmod a+rx /home/hadoop
	chmod -R a+rX "$venv_dir"
	echo "Bootstrap complete. Venv: $venv_dir — $("$venv_dir/bin/python" --version 2>&1)"
}

if [[ -x /databricks/python/bin/pip ]]; then
	PACKAGE_PATH="${PACKAGE_PATH:?Error: PACKAGE_PATH is not set or empty.}"
	setup_databricks
else
	PACKAGE_PATH="${1:?Error: PACKAGE_PATH bootstrap arg is required on EMR.}"
	setup_emr
fi
