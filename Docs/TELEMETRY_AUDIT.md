# Public v1 telemetry audit

Date: August 8, 2026

## Decision

Public v1 ships without a telemetry, analytics, advertising, or crash-reporting provider. Local screening must not depend on remote flags or provider availability.

## Repository audit

- No Firebase, Crashlytics, Sentry, PostHog, Mixpanel, Amplitude, Datadog, New Relic, Instabug, Bugsnag, or App Center dependency is declared.
- No `Logger`, `os_log`, `NSLog`, `print`, or `debugPrint` call records product or screening data.
- The only public user-initiated external URLs are ride-provider handoffs. Guardian networking remains an internal-target concern and has no public route or relay configuration.
- Raw camera frames are not persisted by app code. Local baseline/history records remain inside the protected versioned archive.

## Release gate

`Scripts/check-public-binary.sh` builds the public Release product and inspects the linked image and embedded Frameworks directory for known telemetry providers. It also asserts that public v1 has no URL registration, push entitlement, Guardian relay key, location permission, background mode, or local-network exception.

Adding a provider requires a separate payload inventory, forbidden-field tests, privacy-manifest review, App Privacy updates, a kill switch that cannot block local checks, and an approved retention policy.
