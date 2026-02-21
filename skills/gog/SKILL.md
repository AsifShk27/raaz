---
name: gog
description: Google Workspace CLI for Gmail, Calendar, Classroom, Chat, Drive, Contacts, Tasks, Sheets, Docs, Slides, Forms, and Apps Script.
homepage: https://gogcli.sh
metadata:
  {
    "openclaw":
      {
        "emoji": "🎮",
        "requires": { "bins": ["gog"] },
        "install":
          [
            {
              "id": "brew",
              "kind": "brew",
              "formula": "steipete/tap/gogcli",
              "bins": ["gog"],
              "label": "Install gog (brew)",
            },
          ],
      },
  }
---

# gog

Use `gog` for Gmail/Calendar/Classroom/Chat/Drive/Contacts/Tasks/Sheets/Docs/Slides/Forms/Apps Script. Requires OAuth setup.

Setup (once)

- `gog auth credentials /path/to/client_secret.json`
- `gog auth add you@gmail.com --services gmail,calendar,classroom,chat,drive,contacts,tasks,sheets,docs,slides,forms,appscript`
- `gog auth list`
- If you are upgrading from older scopes, rerun `gog auth add` with the expanded `--services` list above.

Common commands

- Gmail search: `gog gmail search 'newer_than:7d' --max 10`
- Gmail messages search (per email, ignores threading): `gog gmail messages search "in:inbox from:ryanair.com" --max 20 --account you@example.com`
- Gmail send (plain): `gog gmail send --to a@b.com --subject "Hi" --body "Hello"`
- Gmail send (multi-line): `gog gmail send --to a@b.com --subject "Hi" --body-file ./message.txt`
- Gmail send (stdin): `gog gmail send --to a@b.com --subject "Hi" --body-file -`
- Gmail send (HTML): `gog gmail send --to a@b.com --subject "Hi" --body-html "<p>Hello</p>"`
- Gmail draft: `gog gmail drafts create --to a@b.com --subject "Hi" --body-file ./message.txt`
- Gmail send draft: `gog gmail drafts send <draftId>`
- Gmail reply: `gog gmail send --to a@b.com --subject "Re: Hi" --body "Reply" --reply-to-message-id <msgId>`
- Gmail reply with quoted original: `gog gmail send --reply-to-message-id <messageId> --quote --to a@b.com --subject "Re: Hi" --body "Reply"`
- Calendar list events: `gog calendar events <calendarId> --from <iso> --to <iso>`
- Calendar create event: `gog calendar create <calendarId> --summary "Title" --from <iso> --to <iso>`
- Calendar create with color: `gog calendar create <calendarId> --summary "Title" --from <iso> --to <iso> --event-color 7`
- Calendar update event: `gog calendar update <calendarId> <eventId> --summary "New Title" --event-color 4`
- Calendar update with attendee notifications: `gog calendar update <calendarId> <eventId> --send-updates externalOnly`
- Calendar show colors: `gog calendar colors`
- Drive list: `gog drive ls --max 20`
- Drive list only My Drive: `gog drive ls --no-all-drives`
- Drive search: `gog drive search "query" --max 10`
- Drive search only My Drive: `gog drive search "query" --no-all-drives`
- Drive delete (trash): `gog drive delete <fileId>`
- Drive delete permanently: `gog drive delete <fileId> --permanent`
- Contacts: `gog contacts list --max 20`
- Contacts update from JSON: `gog contacts update people/<resourceName> --from-file ./contact.json`
- Sheets get: `gog sheets get <sheetId> "Tab!A1:D10" --json`
- Sheets update: `gog sheets update <sheetId> "Tab!A1:B2" --values-json '[["A","B"],["1","2"]]' --input USER_ENTERED`
- Sheets append: `gog sheets append <sheetId> "Tab!A:C" --values-json '[["x","y","z"]]' --insert INSERT_ROWS`
- Sheets clear: `gog sheets clear <sheetId> "Tab!A2:Z"`
- Sheets metadata: `gog sheets metadata <sheetId> --json`
- Sheets notes: `gog sheets notes <sheetId> "Tab!A1:Z100"`
- Docs export: `gog docs export <docId> --format txt --out /tmp/doc.txt`
- Docs cat: `gog docs cat <docId>`
- Docs comments list: `gog docs comments list <docId>`
- Docs comments add: `gog docs comments add <docId> "Please verify this paragraph."`
- Docs comments reply: `gog docs comments reply <docId> <commentId> "Addressed."`
- Docs comments resolve: `gog docs comments resolve <docId> <commentId>`
- Forms get: `gog forms get <formId>`
- Forms create: `gog forms create --title "Weekly Check-in" --description "Friday async update"`
- Forms responses list: `gog forms responses list <formId> --max 20`
- Forms responses get: `gog forms responses get <formId> <responseId>`
- Apps Script get: `gog appscript get <scriptId>`
- Apps Script content: `gog appscript content <scriptId>`
- Apps Script create: `gog appscript create --title "Automation Helpers"`
- Apps Script create bound script: `gog appscript create --title "Bound Script" --parent-id <driveFileId>`
- Apps Script run function: `gog appscript run <scriptId> myFunction --params '["arg1", 123, true]'`

Google Classroom

- List courses: `gog classroom courses list`
- Get course details: `gog classroom courses get <courseId>`
- Course roster: `gog classroom roster <courseId>`
- List assignments: `gog classroom coursework list <courseId>`
- Get assignment: `gog classroom coursework get <courseId> <workId>`
- Create assignment: `gog classroom coursework create <courseId> --title "Homework" --description "..." --due <iso>`
- List submissions: `gog classroom submissions list <courseId> <workId>`
- Grade submission: `gog classroom submissions grade <courseId> <workId> <submissionId> --draft-grade 95`
- Return submission: `gog classroom submissions return <courseId> <workId> <submissionId>`
- List announcements: `gog classroom announcements list <courseId>`
- Create announcement: `gog classroom announcements create <courseId> --text "Class canceled tomorrow"`
- List students: `gog classroom students list <courseId>`
- List teachers: `gog classroom teachers list <courseId>`
- Invite student: `gog classroom invitations create <courseId> --email student@school.edu --role STUDENT`
- List topics: `gog classroom topics list <courseId>`

Calendar Colors

- Use `gog calendar colors` to see all available event colors (IDs 1-11)
- Add colors to events with `--event-color <id>` flag
- Event color IDs (from `gog calendar colors` output):
  - 1: #a4bdfc
  - 2: #7ae7bf
  - 3: #dbadff
  - 4: #ff887c
  - 5: #fbd75b
  - 6: #ffb878
  - 7: #46d6db
  - 8: #e1e1e1
  - 9: #5484ed
  - 10: #51b749
  - 11: #dc2127

Email Formatting

- Prefer plain text. Use `--body-file` for multi-paragraph messages (or `--body-file -` for stdin).
- Same `--body-file` pattern works for drafts and replies.
- `--body` does not unescape `\n`. If you need inline newlines, use a heredoc or `$'Line 1\n\nLine 2'`.
- Use `--body-html` only when you need rich formatting.
- `--quote` is for reply flows and requires `--reply-to-message-id` (or `--thread-id`).
- HTML tags: `<p>` for paragraphs, `<br>` for line breaks, `<strong>` for bold, `<em>` for italic, `<a href="url">` for links, `<ul>`/`<li>` for lists.
- Example (plain text via stdin):

  ```bash
  gog gmail send --to recipient@example.com \
    --subject "Meeting Follow-up" \
    --body-file - <<'EOF'
  Hi Name,

  Thanks for meeting today. Next steps:
  - Item one
  - Item two

  Best regards,
  Your Name
  EOF
  ```

- Example (HTML list):
  ```bash
  gog gmail send --to recipient@example.com \
    --subject "Meeting Follow-up" \
    --body-html "<p>Hi Name,</p><p>Thanks for meeting today. Here are the next steps:</p><ul><li>Item one</li><li>Item two</li></ul><p>Best regards,<br>Your Name</p>"
  ```

v0.11.0 Notes

- `gog drive delete` now moves files to trash by default. Use `--permanent` for irreversible deletion.
- Drive shared drives are included by default for `drive ls` and `drive search`. Use `--no-all-drives` to scope to My Drive.
- Manual OAuth now uses an ephemeral loopback redirect port (safer local auth flow).
- New command groups are available: `forms` and `appscript`.
- New subcommands are available: `docs comments` and `sheets notes`.
- `gog gmail send --quote` can include quoted original content in replies.

Notes

- Set `GOG_ACCOUNT=you@gmail.com` to avoid repeating `--account`.
- For scripting, prefer `--json` plus `--no-input`.
- Sheets values can be passed via `--values-json` (recommended) or as inline rows.
- Docs supports export/cat/copy. In-place edits require a Docs API client.
- Confirm before sending mail or creating events.
- `gog gmail search` returns one row per thread; use `gog gmail messages search` when you need every individual email returned separately.
