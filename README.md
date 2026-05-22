# Homelab v2.3.10

Proxmox + TrueNAS + Docker service automation package.

## Bootstrap

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.3.10/main/bootstrap.sh)
```

## v2.3.10 focus

- v2.3.8 TrueNAS/Nextcloud NFS hotfix merged.
- v2.3.8 Cloudflared credentials hotfix merged.
- Google OAuth fixed-v4 merged.
- Nextcloud SMTP config restored.
- Jellyfin auto-wizard now sets server name to `Bacsflix`.
- VM107 Chia hardware flow now includes JMicron SATA controller passthrough planning/repair and plot disk automation.
- Maintenance scripts updated for Nextcloud storage, Cloudflared, GPU/JMicron/Chia disk repair, and redacted support bundles.


## v2.3.10

See `docs/HOTFIX-2.3.10.md` for the stabilization/polish changelog.
