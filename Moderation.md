# PulseCore Moderation — v2.6.13

Only Roblox account **wkjkrd**, verified UserId **11409644140**, receives the Moderation tab in the distributed client. Existing Combat/Fun access rules are unchanged. Emotes remains hidden for everyone.

## First use

1. Create a **fine-grained** personal access token at https://github.com/settings/personal-access-tokens/new.
2. Choose resource owner `Marckoq`, **Only select repositories → loader**, and repository permission **Contents → Read and write**. Set an expiration.
3. Start PulseCore as `wkjkrd`, open Moderation, paste the token into the hidden token field, then click **CONNECT GITHUB**. Do not send the token in chat or commit it to a file.
4. Select a repository player, enter a reason and duration, then click **BAN** or **UNBAN**.

The token is held in memory for this run only, cleared by Disconnect or script shutdown, and sent only to `https://api.github.com/repos/Marckoq/loader/...`. It is not stored in configs, files, logs, or the distributed code. A client/executor that intercepts requests can still access a session token; use this only in an environment you trust. GitHub authorization enforces write access; hiding a client tab alone does not provide it.

## Players and search

`Users.txt` is the repository registry, one `UserId|Username` per line; a bare UserId also works. Blank lines and lines beginning with `#` are ignored. Search filters this registry by username or ID. Accounts with a stored ban also appear, including after they leave a game. Players are never taken from the current Roblox server list.

The initial registry contains only `11409644140|wkjkrd`. Add other known users directly to `Users.txt` in GitHub, then press **REFRESH LIST**. Automatic registration of everyone who executes the script has **not** been implemented; a public client cannot safely carry a shared repository-write credential. Presence labels have not been added in this release.

## Duration and enforcement

- Empty Duration: permanent ban.
- `30m`, `2h`, `7d`, `1w`, `1d 2h`: temporary bans.
- A number without a unit means minutes. Zero, negative and malformed durations are rejected.
- Empty Reason becomes `No reason specified`.
- The owner cannot be banned from this UI.
- All successful changes are committed to `Bans.json` in `main`. Each update fetches the latest blob SHA. A concurrent update produces an error instead of overwriting it.
- A ban is checked **before loading the main UI and functions**. Banned users receive only an access notice containing the reason and expiry.
- An expired ban permits access without an Unban action. Expiry is stored as a UTC Unix timestamp; `0` means permanent.
- While running, clients check every 60 seconds. A newly observed ban shuts down the main script and opens the notice. Raw GitHub caching/network delays mean this is not instantaneous.
- The notice has **RECHECK ACCESS**. After unban or expiry, restart PulseCore once the check reports restored access.
- If the initial check fails or the ban document is invalid, ordinary users see an access-check error and the core does not start. A temporary network failure during an existing allowed session does not revoke that session by itself. The owner can still open Moderation to repair repository data.

The repository is public: user records and ban reasons are public too. Avoid writing private information in reasons. This controls the distributed client; it is not a Roblox account/game ban and cannot prevent a user from modifying a client copy to remove the check or running an older copy.

## Verification

Verified locally with Lua 5.4: outer loader and effective source syntax, original compatibility transformations, packed payload/checksum round-trip, duration parsing, expiry, owner restrictions, registry parsing, UTF-8/base64, mocked GitHub Ban/Unban requests, preservation of other records, SHA conflicts, sanitized errors, startup gate and live shutdown flow.

Roblox/executor rendering and a real user-token write were not run in this environment. CONNECT GITHUB checks authenticated reading; GitHub confirms Contents write permission when the first real change is submitted.
