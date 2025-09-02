# Troubleshooting

**AlreadyExists on template**  
→ `make template` first tries create, then update, then delete+create as a fallback. No separate force target needed.

**TLS / x509 unknown authority**  
→ Set `export ARGO_INSECURE_SKIP_VERIFY=true` or supply a CA file via `ARGO_CA_FILE`.

**Cannot parse workflow name on submit**  
→ `make submit` prints a clean URL. If the name can’t be determined, it prints the namespace UI instead.

**Image pull errors**  
→ Ensure the image is public on Docker Hub, or configure an imagePullSecret and add it to the WorkflowTemplate.

**Auth errors**  
→ Get a fresh token from the Argo UI and export: `export ARGO_TOKEN='Bearer <token>'`.

**S3 upload skipped**  
→ If `s3_bucket` is empty, the upload step will no-op. Set `s3_bucket` and optionally `s3_key`. Provide credentials via the `ovh-s3-creds` Secret (preferred) or export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` before `make submit`.

**Wrong namespace**  
→ Ensure `REMOTE_NAMESPACE` matches where you created the `ovh-s3-creds` secret and where your Argo Workflows controller watches. Use `make env` to verify the namespace.
