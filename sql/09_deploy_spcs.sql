USE ROLE AGENT_COMMERCE_ROLE;
USE DATABASE AGENT_COMMERCE;
USE SCHEMA UTIL;

-- NOTE: The container image must be built and pushed to the image repository first.
-- See README for instructions on building and pushing the backend image.

CREATE SERVICE IF NOT EXISTS AGENT_COMMERCE_BACKEND
  IN COMPUTE POOL AGENT_COMMERCE_POOL
  FROM SPECIFICATION $$
  spec:
    containers:
    - name: backend
      image: /agent_commerce/util/agent_commerce_repo/agent-commerce-backend:latest
      resources:
        requests:
          cpu: 0.5
          memory: 1Gi
        limits:
          cpu: 1
          memory: 2Gi
      env:
        SNOWFLAKE_ACCOUNT: <ACCOUNT_LOCATOR>
        SNOWFLAKE_DATABASE: AGENT_COMMERCE
      readinessProbe:
        port: 8000
        path: /health
    endpoints:
    - name: backend
      port: 8000
      public: true
  $$
  MIN_INSTANCES = 1
  MAX_INSTANCES = 1
  EXTERNAL_ACCESS_INTEGRATIONS = (SPCS_BACKEND_ACCESS);
