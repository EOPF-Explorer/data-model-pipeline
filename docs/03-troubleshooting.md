# Troubleshooting

**AlreadyExists on template**  
→ Use `make template-force` to delete and re-apply.

**TLS / x509 unknown authority**  
→ Set `export ARGO_INSECURE_SKIP_VERIFY=true` or supply a CA file via `ARGO_CA_FILE`.

**Cannot parse workflow name on submit**  
→ `make submit` now prints a clean URL. If the name can’t be determined, it prints the namespace UI instead.

**Image pull errors**  
→ Ensure the image is public on Docker Hub, or configure an imagePullSecret and add it to the WorkflowTemplate.

**Auth errors**  
→ Get a fresh token from the Argo UI and export: `export ARGO_TOKEN='Bearer <token>'`.
