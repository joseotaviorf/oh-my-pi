#!/usr/bin/env bash

#####################################################################################
# This script is used to install different types of pex packages on Databricks.
# PEX files that are installed should be built from within the QuintoML ecosystem.
#
# Requirements:
#   - PACKAGE_PATH environment variable needs to be set to a valid S3 path
#   - The package should contain a requirements.txt file with all the dependencies
#   - The package should contain a PEX archive built with tools (i.e. include_tools=True)
#
#####################################################################################

pip install pip==24.0
pip install awscli

mkdir -p artifacts

# It is expected that the content of the PACKAGE_PATH in S3 is the following:
#
# s3://.../SOME_COMMIT_HASH/			# Will mirror the local ./artifacts directory
# ├── requirements.txt
# └── main.pex

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
