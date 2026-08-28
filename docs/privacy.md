# Privacy Policy

AgentDock is local-first. Profile metadata, provider state, chat indexes, and
transcripts remain on the Mac except when a provider application independently
uses its own services.

Optional product analytics are disabled until explicit opt-in. When enabled,
AgentDock sends a random installation identifier and the bounded
[event catalog](analytics.md) to the configured PostHog region. It does not
identify a person or enable automatic capture. Revocation in Data & Privacy
immediately stops collection, clears pending events, and deletes the identifier.

The release operator must publish the selected processing region, approved raw
event retention, analytics contact, and effective date before production
configuration. Until those fields and release variables are set, delivery is
disabled.

See [Security and privacy](security.md), [Data flows](data-flows.md), and the
[security policy](../SECURITY.md) for the remaining boundaries.
