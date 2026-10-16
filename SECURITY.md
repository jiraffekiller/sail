# Security policy

## Supported versions

Only the latest release on the [Releases](../../releases) page receives fixes.

## What Sail does with privileges

Sail itself runs as your user with no special entitlements. The optional helper runs as
root and exposes exactly one write operation over XPC: set the manual charge limit
(an integer from 1 to 100) in PowerUIAgent's preferences and post the notification that
makes it re-read them. It accepts connections only from a client whose code signature
carries Sail's bundle identifier. Release builds are ad-hoc signed, so treat that check
as a courtesy rather than a boundary: the worst a local attacker could do through the
helper is set a charge limit. The helper does not read files, open network connections
or run other programs. See `docs/DESIGN.md`, section 8.

## Reporting a vulnerability

Please open a [GitHub security advisory](../../security/advisories/new) (private) or an
issue if the problem is not sensitive. Include the output of
`/Applications/Sail.app/Contents/MacOS/Sail --status` where relevant. You should hear
back within a week.
