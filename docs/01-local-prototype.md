# Local prototype (deprecated)

This project is now remote-first. Local k3d/kubectl bootstrap and related targets have been removed from the default flow.

Use the remote quickstart in the main README:

```bash
export ARGO_TOKEN='Bearer <paste-from-UI>'
make template
make submit
make logs
make ui
```

Older local notes remain in git history for reference.
