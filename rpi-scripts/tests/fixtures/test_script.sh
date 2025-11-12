#!/usr/bin/env bash
# Test fixture for SARIF scanner
# Contains known security issues for testing

# SEC001: Hardcoded credentials
password="hardcoded123"
api_key="sk-test-1234567890"

# SEC002: Insecure random
random_value=$RANDOM

# QUAL003: Missing error handling
curl https://example.com/api

echo "Test script completed"
