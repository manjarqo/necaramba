# Permission onboarding — 2026-10-14

Reported symptom: Shift and correction appeared to do nothing. Read-only inspection of the running Release app confirmed listen, post and Accessibility all denied. Code inspection additionally confirms automatic correction and editor mutation still have separate qualification gates; this change does not remove them.

Implemented automatic Flutter permission dialog for the first confirmed missing capability, a new native session, or revocation after a fully granted state. It uses native snapshots, explicit request buttons, refresh, RU/EN system-settings guidance, and a restart hint. Dismissal suppresses repeated prompts; a persistent banner reopens the dialog. Granted capabilities hide their request buttons. All granted closes the dialog; this is not a statement that automatic correction is qualified.

Native status/menu now include missing Accessibility. Launch (including background/login launch with missing permissions) opens the UI. Activation and explicit refresh share one permission monitor and refresh the runtime. Actual tap health is queried; changed permissions or an independently stopped tap cause safe recreation. Synchronous callback retirement prevents old/new taps from both delivering physical events. Existing held-event replay is preserved.

Verification: 177 Swift tests (114 Mac +63 Core) and43 Flutter tests PASS; Flutter analyzer clean. Regression RED evidence covers missing dialog, refresh action, grant/revoke ordering, missing AX status, stale runtime health, retired callbacks and the in-flight callback barrier. Scoped review approved both UI and native fixes. No TCC grants, login changes or physical typing tests were performed.

Integrated Release build passed. Actual CUA launch automatically displayed «Разрешите доступ к клавиатуре» with all three denied states, explicit request buttons, Refresh and Later. OS request buttons were not pressed by the agent. Further manual dismissal testing was stopped when computer-use reported user interaction; automated dismissal/reopen tests passed.
