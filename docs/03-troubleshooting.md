# Troubleshooting

Auth/token errors
- Token missing/expired → Get a fresh token from the Argo UI and export:
	`export ARGO_TOKEN='Bearer <token>'`

Template apply errors
- AlreadyExists → `make template` handles create/update; rerun.
- TLS / x509 → set `ARGO_INSECURE_SKIP_VERIFY=true` or provide `ARGO_CA_FILE`.

Submit/logs
- Name parse issues → `make submit` prints a UI link; use `make ui` to navigate.

Image pulls
- Ensure the image is public or configure an imagePullSecret on the WorkflowTemplate.

S3 writes (OVH or other)
- Use `output_zarr` as `s3://bucket/key` and set `s3_endpoint` for non-AWS.
- Provide credentials via Secret `ovh-s3-creds` (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY).
- Check egress to the S3 endpoint.

Namespace mismatches
- `REMOTE_NAMESPACE` must match the namespace with your secrets and where Argo runs.
