# Public v1 telemetry audit

Date: August 8, 2026

## Decision

Public v1 ships without a telemetry, analytics, advertising, or crash-reporting provider. Local screening must not depend on remote flags or provider availability.

This remains the Phase 3 crash-reporting privacy decision. A crash SDK is not
being added merely to satisfy a release checklist: the current product handles
camera-derived measurements, local history, age, a home address, and a trusted
contact. A provider would create a new disclosure, redaction, retention,
deletion, and incident-response surface before public v1 has evidence that the
operational benefit exceeds that privacy cost.

## Repository audit

- No Firebase, Crashlytics, Sentry, PostHog, Mixpanel, Amplitude, Datadog, New Relic, Instabug, Bugsnag, or App Center dependency is declared.
- No `Logger`, `os_log`, `NSLog`, `print`, or `debugPrint` call records product or screening data.
- The only public user-initiated external URLs are ride-provider handoffs. Guardian networking remains an internal-target concern and has no public route or relay configuration.
- Raw camera frames are not persisted by app code. Local baseline/history records remain inside the protected versioned archive.

## Release gate

`Scripts/check-public-binary.sh` builds the public Release product and inspects the linked image and embedded Frameworks directory for known telemetry providers. It also asserts that public v1 has no URL registration, push entitlement, Guardian relay key, location permission, background mode, or local-network exception.

Adding a provider requires a separate payload inventory, forbidden-field tests, privacy-manifest review, App Privacy updates, a kill switch that cannot block local checks, and an approved retention policy.

## Minimum review before adding crash reporting

Do not add a provider until a reviewed encoder proves that every event excludes:

- camera frames, face/eye landmarks, measurements, risk scores, and result state;
- name, age, phone numbers, home label/address, family codes, and Guardian identifiers;
- archive contents, participant IDs, filenames, URLs, and free-form user text;
- precise timestamps or breadcrumbs that reconstruct when checks occurred.

The review must also name the provider, regions, subprocessors, retention,
deletion mechanism, opt-out behavior, DSAR path, incident owner, and App Privacy
answers. Provider startup and failure must never gate Home, a check, a result, or
a get-home action. Until those conditions are met, the compiled-binary no-provider
audit is the release gate.
