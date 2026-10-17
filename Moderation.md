# PulseCore Moderation — v2.6.15

Only Roblox account **wkjkrd**, verified UserId **11409644140**, receives the Moderation tab in the distributed client. Existing Combat/Fun access rules are unchanged. Emotes remains hidden for everyone.

## First use

1. Create a **fine-grained** personal access token at https://github.com/settings/personal-access-tokens/new.
2. Choose resource owner `Marckoq`, **Only select repositories → loader**, and repository permission **Contents → Read and write**. Set an expiration.
3. Start PulseCore as `wkjkrd`, open Moderation, paste the token into the hidden token field, then click **CONNECT GITHUB**. Do not send the token in chat or commit it to a file.
4. Enter an exact Roblox username or UserId in Search Player. A matching account is selected automatically and its full-body avatar is displayed. Enter a reason and duration, then click **BAN** or **UNBAN**.

The token is held in memory for this run only, cleared by Disconnect or script shutdown, and sent only to `https://api.github.com/repos/Marckoq/loader/...`. It is not stored in configs, files, logs, or the distributed code. A client/executor that intercepts requests can still access a session token; use this only in an environment you trust. GitHub authorization enforces write access; hiding a client tab alone does not provide it.

## Players and search

Search Player queries Roblox directly, including accounts that are offline, absent from the current server, or have never used PulseCore. There is no repository player list and `Users.txt` is no longer used.

- Enter an **exact username** (optionally prefixed by `@`) or a **UserId**. Display names and partial names are not unique and are not supported.
- Search starts 0.65 seconds after typing stops. **SEARCH PLAYER** or Enter also starts a search.
- Existence is checked through Roblox account lookup. A valid account is selected automatically, with its current username and UserId.
- The preview requests **AvatarThumbnail**, showing the entire avatar with Fit sizing. **RETRY AVATAR** retries a missing image. An unavailable avatar does not prevent account selection.
- Editing/clearing the query immediately clears the old selection and avatar. Late responses cannot select an older query or replace its image.
- Invalid/missing accounts, network failures and lookup timeouts show an error. **CLEAR SELECTION** also clears the search.
- Search and avatar loading require no GitHub token. Connect GitHub only when saving Ban/Unban. **REFRESH BAN STATUS** reloads published access data without a player list.

## Duration and enforcement

- Empty Duration: permanent ban.
- `30m`, `2h`, `7d`, `1w`, `1d 2h`: temporary bans.
- A number without a unit means minutes. Zero, negative and malformed durations are rejected.
- Empty Reason becomes `No reason specified`.
- The owner cannot be banned from this UI.
- All successful changes are committed to `Bans.json` in `main`. Each update fetches the latest blob SHA. A concurrent update produces an error instead of overwriting it.
- Access checks read `Bans.json` through the GitHub Contents API with a unique request query and no-cache headers. They do not use a raw.githubusercontent.com CDN response. Public clients send no token; the owner can reuse the connected session token. GitHub API availability and rate limits still apply.
- A ban is checked **before loading the main UI and functions**. Banned users receive only an access notice containing the reason and expiry.
- An expired ban permits access without an Unban action. Expiry is stored as a UTC Unix timestamp; `0` means permanent.
- While running, clients check every 60 seconds. A newly observed ban shuts down the main script and opens the notice. The runtime interval and network delays mean this is not instantaneous.
- The notice has **RECHECK ACCESS**. After unban or expiry, restart PulseCore once the check reports restored access.
- If the initial check fails or the ban document is invalid, ordinary users see an access-check error and the core does not start. A temporary network failure during an existing allowed session does not revoke that session by itself. The owner can still open Moderation to repair repository data.

The repository is public: user records and ban reasons are public too. Avoid writing private information in reasons. This controls the distributed client; it is not a Roblox account/game ban and cannot prevent a user from modifying a client copy to remove the check or running an older copy.

## Verification

Verified locally with Lua 5.4: outer loader and transformed core syntax, packed payload/checksum round-trip, username/UserId lookup, invalid and missing accounts, lookup timeout, owner restrictions, duration parsing, UTF-8/base64, mocked authenticated Ban/Unban writes, preservation of unrelated bans, SHA conflicts, and token disconnect. A simulated UI scheduler also verifies debounce, automatic selection, full-body avatar requests, stale search rejection, clearing during lookup, and the selected Ban target. Access-gate tests additionally cover an active ban for `11804391952`, expired/permanent/removed bans, owner exemption, unique API requests, fail-closed startup on unavailable/malformed data, and shutdown on a newly observed ban.

Actual Roblox/executor rendering and real token-authorized writes were not run in this environment. CONNECT GITHUB checks authenticated reading; GitHub confirms Contents write permission when the first real change is submitted.
