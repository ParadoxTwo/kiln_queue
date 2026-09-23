# Known debt and future work

What we know is not right yet, roughly in the order we would tackle it. Each item says why it hasn't been done, because "we didn't get to it" is usually not the whole story.

## Known debt

### The ready-for-collection email lives in a model callback
`Piece` sends `PieceMailer.ready_for_collection` from `after_update_commit` whenever status becomes `finished`. That means a console fix, a backfill or a future admin screen will email members too. It should be an explicit step in the flow that means it.
*Why not yet:* the only path to `finished` today is `Firings::Complete`, so it hasn't hurt anyone.

### Firing page loads pieces and members one row at a time
`firings#show` walks `placement.piece.member` per row. `spec/requests/firings_spec.rb` pins that the query count grows with the load. Flip that spec when fixing it.
*Why not yet:* a kiln holds dozens of pieces, not thousands.

### Monthly statement (legacy)
`Reports::MonthlyStatement` does a query per charge, filters the month in Ruby, adds up floats and prints amounts without a thousands separator, unlike the rest of the app. It has a characterisation spec.
*Why not yet:* it prints the right numbers for every statement so far, and the front desk is used to its layout.

### Saturday class import (legacy)
`Imports::PiecesCsv` swallows every error with a bare `rescue`, so a bad row disappears with only a log line. Running the same file twice imports everything twice. It has a characterisation spec that pins both.
*Why not yet:* the teacher's spreadsheet is usually clean.

### Capacity is check-then-act
`Firings::LoadPiece` reads the remaining space, then inserts. Two people loading the same firing at the same moment can take it over capacity. Same for the "already booked in another firing" check.
*Why not yet:* one technician loads kilns. That will change when the studio opens its second site.

### Studio pass discount and the minimum fee
The discount is applied after the $5.00 minimum, so studio pass members can pay $4.00 for a small piece. Nobody has decided whether that is intended.

## Future work

- **Real staff accounts.** Replace the shared basic auth password with per-person sign-in (Rails 8 authentication generator), so we know who loaded and fired what. Add an audit trail for status changes.
- **Damaged pieces.** The status exists but there is no way to set it from the app, and there is no refund flow.
- **Background jobs in production.** Mail goes through Active Job's default adapter. Add Solid Queue before sending anything that matters, with retries and a dead-letter view.
- **Postgres.** SQLite keeps setup at zero for now. A second site, concurrent staff and reporting would justify moving, and would give us `SELECT ... FOR UPDATE` row locks for the booking rules.
- **Pricing rules in data.** Rates and discounts are constants. When they start changing by date they should live in a table with an effective date, and each charge should keep the rate it was charged at.
- **Load planning.** Technicians load kilns one piece at a time. A suggested load (fill the kiln, oldest pieces first, fair across members) would save them most of an afternoon a week.
- **Member-facing view.** Members ring the front desk to ask where their piece is. A read-only status page per member, reached by a signed link in their email, would stop most of those calls.
