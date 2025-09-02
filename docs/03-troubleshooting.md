# Troubleshooting

- Auth: token missing/expired → refresh in UI and export `ARGO_TOKEN='Bearer …'`.
- Template: AlreadyExists → rerun `make template`. TLS/x509 → set `ARGO_INSECURE_SKIP_VERIFY=true` or use `ARGO_CA_FILE`.
- Submit/logs: if name parsing fails, use the printed link or `make ui`.
- Image pulls: ensure public image or add imagePullSecret on the template.
- S3 writes: set `output_zarr=s3://…` and `s3_endpoint` for non-AWS; create secret `ovh-s3-creds` with AWS keys; verify egress.
- Namespace: `REMOTE_NAMESPACE` must match where your secrets and Argo live.
