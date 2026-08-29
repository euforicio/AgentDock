# Privacy Policy

AgentDock is local-first. Profile metadata, provider state, chat indexes, and
transcripts remain on the Mac except when a provider application independently
uses its own services.

Pseudonymous product analytics are enabled by default. AgentDock sends a random
installation identifier and the bounded
[event catalog](analytics.md) to the configured PostHog region. It does not
identify a person or enable automatic capture. Disabling analytics in Data & Privacy
immediately stops collection, clears pending events, and deletes the identifier.
An explicit prior opt-out is preserved across updates.

Production releases use PostHog's US ingestion region. Raw-event retention
should be limited to 90 days, and aggregate retention must not exceed 13
months. Privacy concerns can be reported through the private security advisory
flow. This policy is effective August 28, 2026. Builds without valid release
configuration cannot deliver analytics.

See [Security and privacy](security.md), [Data flows](data-flows.md), and the
[security policy](../SECURITY.md) for the remaining boundaries.
