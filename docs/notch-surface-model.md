# Notch Surface Model

The island now separates layout from content surface:

- `closed`: collapsed notch only
- `opened + sessionList`: manual browsing of attached sessions
- `opened + approvalCard`: auto-expanded approval interaction
- `opened + questionCard`: auto-expanded question interaction
- `opened + completionCard`: auto-expanded finished-task reminder

Routing rules:

- manual click opens `sessionList`; hover opening is opt-in in General and requires 450ms of pointer intent
- a global click delivered to another app never opens the island
- the closed AppKit window contracts to the rendered pill after the close morph
- only the visible shape accepts mouse events; shadows, transparent corners and outside space pass through natively
- holding Option makes the whole island mouse-transparent so controls directly underneath remain reachable
- outside dismissal observes the original click and never synthesizes another down/up pair
- `permissionRequested` opens `approvalCard`
- `questionAsked` opens `questionCard`
- `sessionCompleted` opens `completionCard`

Auto-expanded cards are temporary surfaces:

- they auto-collapse after a short timeout
- they also collapse when the pointer leaves the card after first hover
- they are not rendered as inline actions inside the session list

This keeps the session list focused on navigation while question and approval
flows use dedicated notification surfaces.

The main DEV window is now a dedicated debug harness for these surfaces. It
drives inline mock previews for the session list plus approval, question, and
completion cards, and it can mirror the currently selected mock onto the real
island overlay for visual inspection.
