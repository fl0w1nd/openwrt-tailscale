<!--
Thanks for sending a pull request! Please fill in the sections below.
Keep it concise — reviewers should be able to grasp the change in 30 seconds.
-->

## Summary

<!-- One or two sentences explaining what this PR changes and why. -->

## Type of change

<!-- Check all that apply. -->

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to break)
- [ ] Refactor / cleanup (no behavior change)
- [ ] Documentation only
- [ ] CI / build / tooling

## Scope

<!-- Which areas does this touch? -->

- [ ] `tailscale-manager.sh`
- [ ] `usr/lib/tailscale/*`
- [ ] `etc/init.d/tailscale`
- [ ] `usr/bin/tailscale-update`
- [ ] `luci-app-tailscale/*`
- [ ] Tests (`tests/`)
- [ ] CI / GitHub Actions
- [ ] Documentation (`docs/`)

## Testing

<!--
How was this verified? Tick all that apply and add details for anything custom.
-->

- [ ] `make lint` passes
- [ ] `make test` passes (default `sh`)
- [ ] `TEST_SHELL=busybox make test` passes
- [ ] `TEST_SHELL=dash make test` passes
- [ ] Manually verified on an OpenWrt device (please specify version + arch)

```
# Paste any relevant output, screenshots, or device info here.
```

## OpenWrt compatibility

<!-- Anything that affects which OpenWrt versions / hardware are supported. -->

- Affects RAM-only mode? `yes / no`
- Affects userspace fallback? `yes / no`
- Touches firewall / network UCI? `yes / no`

## Checklist

- [ ] Code follows the conventions in `AGENTS.md`
- [ ] Commit message follows Conventional Commits (`feat:`, `fix:`, `docs:`, ...)
- [ ] No secrets, credentials, or device-specific paths committed
- [ ] Tests added/updated for behavioral changes
- [ ] `VERSION="..."` in `tailscale-manager.sh` bumped if this is a user-facing release

## Related issues

<!-- e.g. Closes #123 / Refs #456 -->
