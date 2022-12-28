# Instance running aws-ses-pop3-server

This directory contains terraform which creates a very small instance to run the
aws-ses-pop3-server, and a handler for doing the authentication and getting S3
credentials.

This is not suitable at scale - for that consider multiple ECS containers behind
an NLB.

Run:

```
BUCKET="<name of your terraform storage bucket>"
REGION="<region of your terraform storage bucket>"
echo bucket="${BUCKET}" >backend.hcl
echo region="${REGION}" >>backend.hcl
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## TODO

*   ASG Health monitor
*   ASG Hold previous for 10 minutes
*   Route53 Integration
*   Notifications of bad ASG health
*   Monitoring, incl delivery stats?
*   Logs export to cloudwatch
*   TLS
*   Auth-proxy: Expiry of lru_cache - ratelimit user auths instead
*   Auth-proxy: exception as JSON
*   Auth-proxy: HTTP log as JSON
*   Open inbound TCP port
*   Change to using ECS