# Exchange runner contract

The Microsoft Exchange Online connector cannot run PowerShell: the connector sandbox allows HTTP only. It sends
each Exchange cmdlet to the **Exchange runner**, a separate service that runs the cmdlet with the official
`ExchangeOnlineManagement` module and returns the result. This file is the contract between the two. The runner
is built in its own repository; the connector's specs stub it with exactly these shapes.

## Endpoint

```
POST {runner_url}/v1/cmdlets
Authorization: Bearer <runner API key>
Content-Type: application/json
```

The call is synchronous. The connector waits up to 65 seconds (5 to connect), which leaves room for opening a
session for a tenant the runner has not seen yet.

### Request body

```json
{
  "organization": "contoso.onmicrosoft.com",
  "exchange_environment": "O365Default",
  "access_token": "<app-only token for the tenant's Exchange host>",
  "cmdlet": "Add-MailboxPermission",
  "parameters": {
    "Identity": "support@contoso.com",
    "User": "jane@contoso.com",
    "AccessRights": ["FullAccess"],
    "InheritanceType": "All",
    "AutoMapping": true
  }
}
```

| Field | Meaning |
|---|---|
| `organization` | The tenant's initial domain. Passed to `Connect-ExchangeOnline -Organization`. |
| `exchange_environment` | `O365Default`, `O365USGovGCCHigh`, `O365USGovDoD` or `O365China`. Passed to `-ExchangeEnvironmentName`. |
| `access_token` | An app-only token for `https://outlook.office365.com/.default` (or the cloud's Exchange host), obtained by the connector with the customer's app registration. Passed to `-AccessToken`. The runner stores no customer credentials and must never log this value. |
| `cmdlet` | One of the allow-listed cmdlets below. Anything else is refused with 422 and never run. |
| `parameters` | Splatted onto the cmdlet. JSON `true`/`false` become `$true`/`$false`, arrays become arrays, and an object such as `{ "add": ["x"] }` becomes a hashtable (`@{ Add = @('x') }`) for multi-valued properties. |

### Allow-list

```
Get-Mailbox  Set-Mailbox  New-Mailbox  Get-MailboxStatistics
Get-MailboxPermission  Add-MailboxPermission  Remove-MailboxPermission
Get-RecipientPermission  Add-RecipientPermission  Remove-RecipientPermission
Get-Recipient  Get-AcceptedDomain
Get-DistributionGroup  Add-DistributionGroupMember  Remove-DistributionGroupMember
Get-MailboxFolderStatistics  Get-MailboxFolderPermission  Add-MailboxFolderPermission  Set-MailboxFolderPermission
```

The connector keeps the same list in `RUNNER_CMDLETS` and refuses anything else before calling the runner.

## Responses

### Success: 200

```json
{ "output": [ { "Identity": "support", "User": "CONTOSO\\jane", "AccessRights": ["FullAccess"] } ] }
```

`output` is always a list: the objects the cmdlet wrote to the pipeline, empty when it wrote none. Each object
is serialized one level deep. Values that are not strings, numbers, booleans or lists of those are written as
their `ToString()`; in particular `TotalItemSize` must arrive as Exchange prints it, for example
`"1.2 GB (1,288,490,188 bytes)"`, because the connector reads the byte count from it.

### Failure

```json
{
  "error": {
    "category": "not_found",
    "error_id": "[Server=AM0PR01][FailureCategory=Cmdlet-ManagementObjectNotFoundException] 5F6A...",
    "message": "The operation couldn't be performed because object 'x' couldn't be found."
  }
}
```

| Status | When | Connector does |
|---|---|---|
| 400 | Exchange rejected the cmdlet (bad value, already a member, and so on) | Fails the step with `message`, unless `error_id` names an exception below |
| 401 | Runner API key missing or wrong | Fails: "The Exchange runner refused its API key." |
| 403 | Exchange refused the token or the app lacks the role | Fails and names `Exchange.ManageAsApp` and the Exchange role |
| 404 | The object named in `Identity` does not exist | Fails with `message`, unless `error_id` names an exception below |
| 422 | Cmdlet not on the allow-list, or a parameter not allowed | Fails with `message` |
| 429 | Exchange throttled the tenant | Pauses the step for `Retry-After` seconds, then runs it again |
| 502 | `Connect-ExchangeOnline` failed | Fails with `message` |
| 503 | Runner overloaded or shutting down | Pauses the step for `Retry-After` seconds (60 without it) |
| 504 | The cmdlet took longer than the runner's own limit | Fails with `message` |

`error_id` is the PowerShell error's `FullyQualifiedErrorId`, passed through unchanged. The connector matches
these exception names in it, so the runner must not rewrite them:

| Exception name | Cmdlet | Connector treats it as |
|---|---|---|
| `MemberAlreadyExistsException` | Add-DistributionGroupMember | Success, `changed: false` |
| `MemberNotFoundException` | Remove-DistributionGroupMember | Success, `changed: false` |
| `ManagementObjectNotFoundException` | Get-Recipient | "No recipient holds this address" |
| `UserNotFoundInPermissionEntryException` | Get-MailboxFolderPermission | "User has no entry on this folder" |

`category` is informational (`invalid`, `not_found`, `forbidden`, `unauthorized`, `throttled`, `internal`); the
connector shows it in the failure message but does not branch on it.

## Still to confirm against a live tenant

- `Connect-ExchangeOnline -AccessToken` with an app-only client-credentials token, in the module version the
  runner pins.
- The four exception names above, by triggering each case once.
- The Exchange host and token resource for **US Government DoD** (`https://webmail.apps.mil`) and **China**
  (`https://partner.outlook.cn`).
- The JSON shape of `GrantSendOnBehalfTo`, `EmailAddresses`, `AccessRights` and `SharingPermissionFlags` as the
  runner serializes them. The connector accepts either a list or a comma-separated string for `AccessRights`
  and `SharingPermissionFlags`.

## Platform side

When a connection leaves **Runner URL** empty, the connector reads `exchange_runner_url` and
`exchange_runner_api_key` from the solution environment. iPaaS must provide both for every account where the
connector is enabled; the key must arrive as a secret string, because the connector decrypts it.
