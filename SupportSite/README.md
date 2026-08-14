# Sober public support site

These static files are the ready-to-host App Store Support URL and Privacy
Policy URL content. They intentionally describe only the public, local-only
`Sober` target.

Before publishing:

1. Confirm `pulavarthyvinay@gmail.com` is the monitored public support address,
   or replace it in both HTML files.
2. Publish the directory at a stable HTTPS origin with no authentication.
3. Use the root page as App Store Connect's Support URL and `privacy.html` as
   its Privacy Policy URL.
4. Verify both URLs on cellular data and retain screenshots with the candidate
   release evidence.
5. Republish these pages whenever the app adds a server, SDK, data collection,
   permission, or retention change.

Do not publish this directory from the private repository as a raw file URL.
Use an actual static host so links, mobile layout, and contact information stay
available to customers and App Review.
