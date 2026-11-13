## Summary

Closes #

## Checks

- [ ] CI is green.
- [ ] If the PR changes the overlay, the menu, Settings or the welcome window:
      I downloaded the screenshots from CI and looked at them
      (`gh run download <run-id> --repo zerone0x/mac-live-captions --pattern '*screenshots*'`,
      see [docs/TESTING.md](../docs/TESTING.md#screenshots-from-ci)).
- [ ] If the PR touches capture, speech, the notch or permissions: the manual
      checks in [docs/TESTING.md](../docs/TESTING.md) were run on a real Mac,
      or the PR says which ones are still open.
