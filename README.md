# Timezone Converter

A Droplet for [Droppy](https://getdroppy.app), built with
[DroppyKit](https://getdroppy.app/docs/droppykit).

One moment, every timezone you keep. Type a time the way you say it —
“3pm New York”, “tomorrow 9:30 Berlin”, “mon 10 utc+5” — or pick it, and
read it in each of your zones at once, with day shifts (“+1d”) and offsets
(“+8h”) on every row. Opens on the current time, so it doubles as a world
clock; “Now” brings it back. Copy any row to the pasteboard for the chat
where the meeting is being arranged.

## Using it

- **Rulers:** the time of day is set by scrubbing two tick rulers — hours,
  and minutes in 15-minute blocks — with a fixed needle in the centre; drag
  the strip, scroll with the trackpad, or tap a tick. Each step ticks, and
  the strip stops at its ends. The day steps with ‹ › around the date.
- **Day colors:** the hour ruler is a gradient of the day — deep blue night,
  soft orange morning, golden midday, soft purple evening — and every
  result row's time is tinted with its city's local part of day, so day and
  night read at a glance.
- **Query field:** time first (“3pm”, “15:00”, “9.30am”, “noon”), then a
  zone if the current source isn't the one you mean (“3pm Tokyo”). Day words
  work too: “today”, “tomorrow”, weekday names, “next monday”. A line under
  the field shows how the query reads; press ↩ to apply.
- **Zone sources:** IANA city names, common aliases (NYC, LA, Beijing,
  Mumbai, …), and fixed offsets (`utc+5:30`, `gmt-3`).
- **Zones list:** the “Edit” button beside the query field opens the
  editor — add zones by typing a city and choosing a suggestion, remove
  with −. The list and the source zone persist between uses.

## Developing

```bash
droppykit run        # open it in Droppy's Settings panel
droppykit build      # produce TimezoneConverter.droplet
droppykit validate   # the checks the Store repository runs
droppykit submit     # open the merge request that puts it in the Store
```

## With a coding agent

Open this folder in Claude Code, Codex or Cursor. `AGENTS.md` is the brief
they read first, and `.mcp.json` / `.cursor/mcp.json` connect the DroppyKit
MCP server, which gives them the build, the checks, pictures of every surface
and an install into Droppy Playground as tools. Codex registers the server
once per Mac: `codex mcp add droppykit -- path/to/droppykit/Scripts/droppykit mcp`.
Run `droppykit agent` again after moving this folder or the SDK checkout.

## Before submitting

- Leave `TimezoneConverter.icon` as it is. It is a placeholder for the harness:
  Jordy designs every Store droplet's icon, and `droppykit submit` leaves it
  out. Have an idea for yours? Put it in the merge request's Icon concept
  section.
- Replace `Assets/Creator.png` with your own square, unrounded mark.
- Fill in `summary`, `description` and `creator` in `droplet.json`, and
  write `CHANGELOG.md`.
- `droppykit submit`: the Store is a repository, one folder per droplet, and
  this opens the merge request that adds yours. See
  [Submitting](https://getdroppy.app/docs/droppykit/submitting).
