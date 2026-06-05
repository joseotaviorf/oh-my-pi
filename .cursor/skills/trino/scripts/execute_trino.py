#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["trino", "pandas", "keyring"]
# ///
import sys
import argparse
import json
import os
import pandas as pd
from trino.dbapi import connect
from trino.auth import BasicAuthentication, OAuth2Authentication

def run_query(query, host, port, user, catalog=None, schema=None, password=None, external_auth=False):
    try:
        if external_auth:
            # OAuth2Authentication automatically uses KeyRingTokenCache if keyring is installed
            auth = OAuth2Authentication()
        else:
            auth = BasicAuthentication(user, password) if password else None
            
        conn = connect(
            host=host,
            port=port,
            user=user,
            catalog=catalog,
            schema=schema,
            http_scheme='https' if port == 443 else 'http',
            auth=auth
        )
        
        # Use pandas for native data handling
        df = pd.read_sql_query(query, conn)
        
        # Handle non-serializable objects (like Timestamps)
        for col in df.columns:
            if pd.api.types.is_datetime64_any_dtype(df[col]):
                df[col] = df[col].astype(str)
        
        # Return as JSON for agent consumption
        result = {
            "status": "success",
            "columns": list(df.columns),
            "data": df.values.tolist(),
            "count": len(df)
        }
        return result
        
    except Exception as e:
        return {"status": "error", "message": str(e)}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", required=True)
    parser.add_argument("--host")
    parser.add_argument("--port", type=int, default=443)
    parser.add_argument("--user")
    parser.add_argument("--catalog")
    parser.add_argument("--schema")
    parser.add_argument("--password")
    parser.add_argument("--external-auth", action="store_true")
    
    args = parser.parse_args()
    
    # Priority: Command line arg > Environment variable
    host = args.host or os.environ.get("TRINO_HOST")
    
    # For OAuth2, user can often be a placeholder or extracted from token
    # If not provided, we use a generic placeholder or environment user
    user = args.user or os.environ.get("TRINO_USER") or "quinto-agent"
    
    if not host:
        print(json.dumps({"status": "error", "message": "Trino host not provided. Please set TRINO_HOST environment variable or use --host."}))
        sys.exit(1)
    
    res = run_query(
        args.query, 
        host, 
        args.port, 
        user, 
        args.catalog, 
        args.schema, 
        args.password, 
        args.external_auth
    )
    
    print(json.dumps(res))
