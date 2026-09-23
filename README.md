# Kiln Queue

Firing scheduler for a community pottery studio.

Members hand in pieces they have made. Staff load them into kiln firings, first a low **bisque** firing and then, once the member has glazed the piece, a hot **glaze** firing. After the glaze firing the member pays a fee and collects the piece from the front desk.

Staff use the app to:

- take pieces in and follow them through the studio
- plan firings and load pieces into them, with checks for stage, temperature, double booking and shelf space
- mark a firing as fired, which moves every piece on a stage and charges members for glaze firings
- print a monthly statement per member
- import the spreadsheet a teacher hands over after each Saturday class

The app is small, but it is built the way a production Rails app should be: validations and a unique index on every invariant, service objects that return results instead of raising, money kept in integer cents, request, model, service and mailer specs, CI, a Dockerfile, a health check and basic auth. It also carries some **legacy corners and known debt on purpose**, because that is what a real codebase looks like and the practice questions below need something to work on.

> **This repo is also a rehearsal kit for a live pairing interview.** The second half of this README is for the interviewer. If you are the candidate, stop at [Rehearsal](#rehearsal) and let the interviewer drive.

---

## Setup

You need Ruby 3.2 or newer and SQLite 3. Nothing else: no Postgres, no Redis, no Node.

```sh
# .ruby-version says 3.3.6. On another 3.2+ Ruby, edit that file (or delete it) first.
bundle install
bin/rails db:setup                                     # create, migrate, seed
bin/rails "kiln:import[db/sample/saturday_class.csv]"  # optional: last Saturday's class
bin/rails server                                       # http://localhost:3000
```

Run the checks:

```sh
bundle exec rspec        # 56 examples
bin/rubocop              # rubocop-rails-omakase
bin/brakeman --no-pager  # static security scan
bin/ci                   # all of the above, as CI runs them
```

Set `STAFF_PASSWORD` (and optionally `STAFF_USERNAME`, default `staff`) to put every page behind HTTP basic auth. Production sets it.

## The domain

```
Member ──< Piece ──< Placement >── Firing >── Kiln
   │         │
   └───< Charge >┘
```

A piece moves through:

```
submitted ──bisque firing──> bisqued ──member glazes──> glazed ──glaze firing──> finished ──pick up──> collected
                                              (any open state can become damaged)
```

| Rule | Where it lives |
|---|---|
| A bisque firing takes `submitted` pieces, a glaze firing takes `glazed` ones | `Firings::LoadPiece` |
| A glaze firing only takes pieces whose glaze matures within ±10C of its target | `Firing::GLAZE_TOLERANCE_C` |
| A piece can only be booked into one planned firing at a time | `Firings::LoadPiece` |
| Pieces take up their bounding box volume. A firing cannot go over the kiln's capacity | `Firing#remaining_capacity_cm3` |
| A firing's target cannot be hotter than its kiln allows | `Firing` validation |
| Glaze fee: 3c per cm3, $5.00 minimum, studio pass members get 20% off after the minimum, rounded half up once | `Pricing::PieceFee` |
| When a piece is finished, the member gets an email | `Piece` callback (known debt) |

### Where things are

```
app/services/result.rb                   success/failure value returned by every service
app/services/firings/load_piece.rb       all the loading rules, in order
app/services/firings/complete.rb         fire a kiln: move pieces on, charge members
app/services/pricing/piece_fee.rb        the fee, in cents, with BigDecimal
app/services/reports/monthly_statement.rb   LEGACY
app/services/imports/pieces_csv.rb          LEGACY
app/lib/money.rb                         Money.format(123456) => "$1,234.56"
spec/support/query_counter.rb            count_queries { ... } for proving N+1 fixes
```

The legacy files have **characterisation specs**: they pin what the code does today, including behaviour that is probably wrong, marked `(pinned as-is)`. Change them on purpose, not by accident.

Known debt and future work are in [FUTURE.md](FUTURE.md).

---

## Rehearsal

This kit rehearses a pairing session where:

- the code runs on the **interviewer's** machine and the candidate joins through **VS Code Live Share** as a guest, sharing their screen on a video call
- the problem is "a relatively straightforward one the team worked on recently"
- AI tools are allowed, but the interviewer may ask for part of it to be talked through without AI
- a CTO drives the conversation and a QA engineer watches the edge cases and the tests

### How to run it (for Ankit)

1. **Host it.** Clone and set up the app on your machine, check `bundle exec rspec` is green, open the folder in VS Code and start a Live Share session. Send Edwin the link. Share a terminal with him (read/write) so he can run specs. That is the thing most likely to be awkward on the day, so it is worth rehearsing.
2. **Call.** Get on Google Meet. Edwin shares his screen.
3. **Orient (5 min).** Give him the one-paragraph pitch at the top of this README and nothing else. Watch how he finds his way round code he has not seen.
4. **Pick one set (40-60 min).** Read the opening prompt out as written. Only move to a follow-up when he has finished or stalled on the step before. You will not get through every follow-up, and you should not try to. The interviewer notes under each set are for you: open them, he should not.
5. **Play two people.** Alternate between the CTO voice (design, trade-offs, "why") and the QA voice (edge cases, "how do you know it works", "what would you test by hand"). Each set has prompts for both.
6. **One no-AI checkpoint per session.** At some point say "close the AI pane and talk me through this part". Each set suggests where.
7. **Debrief (10 min).** Use the [scorecard](#scorecard) at the end.

Run a different set each time. Sets 1 and 3 are the closest to what an e-commerce team is likely to hand over, so if there is only time for two rehearsals, do those.

---

## Set 1: Refactor the monthly statement

### Opening prompt

> "The front desk prints a statement for every member at the end of the month. It's slow now that we have a few hundred members, and the numbers look slightly different from the rest of the app. Could you refactor `Reports::MonthlyStatement`? It should keep printing exactly the same thing unless you and I agree to change it."

### Follow-ups, in order

1. "Before you touch it, how do you know you haven't broken it?"
2. "How many queries does it issue for a member with 30 charges? Show me."
3. "You filter the month in Ruby. Why does that matter, and what's the fix?"
4. "Totals are floats. Can you show me a case where that gives the wrong answer?"
5. "The spec pins `$1234.56` with no comma, and the rest of the app prints `$1,234.56`. Should we fix it? Who would you ask?"
6. **Bug report:** "A member was charged at 9am on 1 October and it appeared on her *September* statement."
7. "Accountants now want a CSV export of the same statement. How would you shape the code so the text version and the CSV version share the numbers but not the formatting?"
8. **QA voice:** "Give me the five test cases you'd want for this before we ship it."
9. **No-AI checkpoint:** "Close the AI pane. Explain `includes` vs `preload` vs `eager_load`, and which one you used here."
10. **Stretch:** "Statements for all 400 members, as one PDF, overnight. Where does this run and what happens when member 212 blows up?"

<details>
<summary><b>Interviewer notes: Set 1</b></summary>

**Good looks like**

- Finds and runs the characterisation spec first (`spec/services/reports/monthly_statement_spec.rb`), and keeps it green through small steps. Commits (or at least describes) each step on its own: queries, then money, then output.
- Proves the N+1 with `count_queries` from `spec/support/query_counter.rb` before and after.
- Replaces the per-charge `Piece.find` with `member.charges.includes(:piece)` (or a join), and filters in SQL: `where(created_at: month.all_month)` or a range on the local month's start and end.
- Sums integer cents (`sum(:amount_cents)`), formats once with `Money.format`. Recognises `0.1 + 0.2 != 0.3` style drift. Mentions BigDecimal or cents, not `round(2)` on floats.
- Splits "gather the lines" from "format the lines" (a small value object or `Data.define` for a line, a formatter for text). That also answers follow-up 7 cleanly.
- On follow-up 5: does not silently change pinned behaviour. Says "it's a visible change for staff, I'd check with whoever owns the printout", and then updates the spec deliberately.
- On the time zone bug, the cause is that the app runs in UTC and the studio is in Melbourne. Fix: `config.time_zone = "Melbourne"` in `config/application.rb`, and a spec with `travel_to` on either side of midnight. Bonus: points out stored timestamps stay UTC, only interpretation changes. Bonus: notices the month param and `Date.current` also depend on it.

**Weak signals**

- Rewrites the whole thing in one go, then runs the spec.
- Changes the output format without noticing.
- "Floats are fine for money if you round."
- Can't show the query count, only asserts it.

**QA prompts:** empty month, a member with no charges, a charge at exactly 23:59:59 on the last day, a deleted piece, a studio pass member (the line says the discount was applied, but the amounts already include it: is that clear to a member?).

</details>

---

## Set 2: Change how members are told a piece is ready

### Opening prompt

> "When a piece comes out of a glaze firing, the member gets an email straight away. Staff want to check pieces first. Sometimes a glaze runs or a pot cracks. So: finishing a firing should no longer email anyone. Staff will press a 'Notify members' button on the firing once they've checked the shelf, and that sends the emails. Could you make that change?"

### Follow-ups, in order

1. "Where is the email sent from today? What else triggers it?"
2. "Show me the test that proves an email is sent once per piece when staff press the button, and zero times when the firing completes."
3. "Staff press 'Notify' twice by accident. What happens? What should happen?"
4. "A piece cracked. Staff need to mark it damaged before notifying. Add that, and make sure the member of a damaged piece gets a different email, or none. Your call, tell me why."
5. **Bug report:** "Tom was charged twice for the same serving platter last month. The front desk thinks someone double-clicked 'Mark as fired'."
6. "Should a damaged piece have been charged at all? What would you change in `Firings::Complete`?"
7. **QA voice:** "How would you test the double-click without a browser?"
8. **No-AI checkpoint:** "Close the AI pane. What does `deliver_later` do inside a transaction that then rolls back? How does this app avoid that?"
9. **Stretch:** "We move to SMS for some members. What changes and what doesn't?"

<details>
<summary><b>Interviewer notes: Set 2</b></summary>

**Good looks like**

- Removes the callback and moves the side effect somewhere explicit: a `Firings::NotifyMembers` service called by a new controller action. Explains why: callbacks run on *every* save path, including consoles and backfills, and hide the business flow.
- Spec uses `have_enqueued_mail(PieceMailer, :ready_for_collection)` (ActiveJob test adapter is on) and `.exactly(n).times`, plus a spec that `Firings::Complete` enqueues nothing.
- Makes notify idempotent: a `notified_at` column on the firing (or on each piece), set in the same transaction, guarded with a conditional update. Knows a boolean alone does not stop two concurrent requests.
- **The double charge is real.** `Firings::Complete` checks `@firing.planned?` on an object loaded before the transaction, so two requests both pass the check. Try it: load the same firing twice with `Firing.find` and call `Complete` on each. Two charges. Good fixes, any of:
  - `@firing.with_lock { return failure unless @firing.planned?; ... }` (re-reads the row under a lock; on SQLite the write lock serialises, on Postgres `SELECT ... FOR UPDATE`)
  - a conditional update: `Firing.where(id:, status: "planned").update_all(status: "fired", ...)` and only carry on if it returned 1
  - plus a belt: a `firing_id` on charges with a unique index on `[firing_id, piece_id]`
- Spots that a damaged piece should not be moved to `finished` or charged, and changes `Complete` to skip damaged pieces. Asks whether a refund or credit is needed for existing cases.
- Rails 7.2+ can defer job enqueueing until the transaction commits (`enqueue_after_transaction_commit`). He should know the problem even if he has to look up the setting: an email for a charge that never happened.

**Weak signals**

- Adds `unless` conditions to the callback instead of removing it.
- Disables the button in JavaScript and calls the double charge fixed.
- No test for "zero emails".

**QA prompts:** notify on a bisque firing (should do nothing or be hidden), notify on a planned firing, a member with no email, a piece collected before notify, and "how would you know in production that emails actually went out?"

</details>

---

## Set 3: Update pricing for GST and a new tier

### Opening prompt

> "The studio has registered for GST. From 1 November, glaze fees are GST-inclusive at 10%: the price members pay doesn't change, but every charge and statement needs to show how much of it is GST. At the same time we're adding a **concession** tier, 30% off. Could you make those changes?"

### Follow-ups, in order

1. "Talk me through where money is calculated, stored and displayed before you start."
2. "How do you work out the GST in a GST-inclusive price? Show me with $24.02."
3. "Do you store the GST on the charge, or calculate it when printing? Why?"
4. "Charges from October must not change. Prove it."
5. "Does the $5.00 minimum apply before or after the concession discount? What does the code do today for studio pass members, and is it what the business wants?"
6. "Next year the rate goes from 3c to 3.5c per cm3 from 1 July. Where should the rate live so that doesn't need a deploy?"
7. **QA voice:** "Give me the boundary cases for rounding. Which ones would you put in the spec?"
8. **No-AI checkpoint:** "Close the AI pane. Why BigDecimal and not Float here? What does ROUND_HALF_UP do with 2.5 and -2.5, and what does banker's rounding do instead?"
9. **Stretch:** "A kiln cracks a piece and we refund the member. How do refunds show up on a statement, and in the GST total?"

<details>
<summary><b>Interviewer notes: Set 3</b></summary>

**Good looks like**

- Adds `concession` to `Member::TIERS` and a discount table keyed by tier instead of another `if`. Reads `PieceFee` spec first; adds rounding cases for the new rate the way the existing ones are written.
- GST on an inclusive amount is `amount * 1/11`, rounded once. $24.02 contains $2.18 of GST (2.1836...). Recognises that summing per-line rounded GST can differ from GST on the total by a cent, and picks one on purpose (per line is normal on a tax invoice, and it is what is stored).
- Stores `gst_cents` (and ideally the rate used) on each charge at the time of charging: prices and rules change, history must not. A migration with a default of 0 for existing rows, not a backfill that invents GST for October.
- Makes the rule effective-dated: by `charged_at` (or firing date, he should ask which), not by `Date.current` at print time.
- On the minimum: notices the current order lets a studio pass member pay less than the minimum, and asks rather than guesses.
- Rate in the DB with `effective_from` (a `price_rules` table) or at least configuration, with a spec that time-travels across the change.

**Weak signals**

- 10% of the price.
- Floats anywhere, `round(2)` on dollars.
- Recalculates GST when printing old statements.
- Changes behaviour for existing tiers without flagging it.

**QA prompts:** a 1cm3 piece, a piece exactly at the minimum, the largest piece the kiln takes, a member whose tier changes mid-month (which tier applies to which charge?), the charge created at 23:59 on 31 October.

</details>

---

## Set 4: Improve the Saturday class import

### Opening prompt

> "After each Saturday class the teacher gives the front desk a spreadsheet and they run `bin/rails kiln:import[...]`. Last week Tom said his ramen bowl was never fired, and nobody could work out why. Could you improve the import so this can't quietly happen again?"

### Follow-ups, in order

1. "Run it against `db/sample/saturday_class.csv`. What happened to the ramen bowl?"
2. "What should the front desk see after an import? Design the output first, then build it."
3. "They ran it twice by mistake. What happened, and how do you make a second run safe?"
4. "If row 3 is bad, should rows 1, 2, 4 and 5 still go in? Argue both sides, then pick."
5. "`rescue => e` then `next`. What's wrong with that, specifically?"
6. "Now they want to upload the CSV through the web page instead of using the terminal. What changes in your design?"
7. **QA voice:** "Write me the list of nasty CSVs you'd test with."
8. **No-AI checkpoint:** "Close the AI pane. Why does `'abc'.to_i` not raise, and what would you use instead?"
9. **Stretch:** "A 20,000 row import from another studio. What breaks first?"

<details>
<summary><b>Interviewer notes: Set 4</b></summary>

**Good looks like**

- Finds it quickly: `"abc".to_i` is 0, the `> 0` validation fails, the bare `rescue` swallows it, the only trace is a log line. The characterisation spec pins exactly this.
- Returns a per-row report: a `Result` per row, or a small `Report` object with created, skipped (with row number and reason) and failed. The rake task prints it. `Integer(value, exception: false)` or `Integer(value)` with a rescue that records the reason.
- Idempotency: a natural key (member + title + class date), or an `import_batch` table with a checksum of the file, or `source_row_ref`. Pushes back on "just make title unique", which is wrong (people make two tea bowls).
- All-or-nothing vs partial: either is defensible. Good answers tie it to the user: "the front desk can fix one row and rerun, so partial plus a clear report plus idempotency works; all-or-nothing is simpler if they'd rather fix the file".
- Rescues specific errors (`ActiveRecord::RecordInvalid`, `CSV::MalformedCSVError`, `ArgumentError`), not `StandardError`. Says the bare rescue also hides real bugs.
- For the web upload: parse in a job, store the upload, show the report on a page, and keep the same service object so the rake task still works.

**Weak signals**

- Adds a `puts` in the rescue and calls it done.
- Unique index on title.
- Rewrites the characterisation spec to pass instead of changing it on purpose.

**QA prompts:** the member row has a new email for an existing name, the file is empty, the file has only headers, two identical rows in one file (two tea bowls is legitimate), a row with a glaze temperature no kiln can reach.

</details>

---

## Set 5: New feature, suggest a kiln load

### Opening prompt

> "Loading a kiln is the slowest part of the technician's week. They go down the waiting list and click 'Load' one piece at a time. Could you add a 'Suggest a load' button on a planned firing that proposes which waiting pieces to put in, and lets them accept it in one go?"

### Follow-ups, in order

1. "Before code: what makes a load 'good'? Who would you ask?"
2. "Sketch the algorithm. What's its complexity, and does that matter at our size?"
3. "Where does this code live, and what does it depend on? Could you test it without the database?"
4. "Build the suggestion, show it on the page, and let staff accept it."
5. "Two technicians accept suggestions for the same piece in two different firings at the same moment. What happens?"
6. "A member can't have more than 30% of a kiln. Add that rule. Where does it go?"
7. **QA voice:** "What would you test? What's the one property that must always be true, whatever the input?"
8. **No-AI checkpoint:** "Close the AI pane. First-fit decreasing vs oldest first: what do you lose with each?"
9. **Stretch:** "Pieces aren't boxes and shelves have heights. How would you know if the suggestions are actually any good in the real kiln?"

<details>
<summary><b>Interviewer notes: Set 5</b></summary>

**Good looks like**

- Asks questions first: fairness vs utilisation, whether staff can tweak the suggestion, whether it should respect the temperature window and stage (it must: reuse the rules, don't copy them).
- A pure planner object: takes a capacity and a list of plain candidates (id, volume, member, waiting since), returns a list of ids. No ActiveRecord inside, so it's fast to test with plain structs. A thin service loads candidates and applies the plan through the existing `Firings::LoadPiece`, so every rule is still checked once.
- Knows this is bin packing and that it's NP-hard in general, and that a greedy heuristic is fine for one kiln: oldest first with a fits check is fair; largest first (first-fit decreasing) packs better. A reasonable hybrid: oldest first, skipping pieces that don't fit, then fill gaps. O(n log n) for the sort, trivial at this size.
- Accepting the suggestion is atomic: one transaction, and a failure in `LoadPiece` for any piece is reported, not swallowed. Mentions re-checking because the waiting list can change between suggesting and accepting.
- On the race: `LoadPiece`'s "already booked" check is check-then-act. Two firings can each take the same piece. Fix with a lock or, better, a DB constraint: an index can't see the firing's status from the placements table, so either a `booked_firing_id` on pieces set with a conditional update (`where(booked_firing_id: nil)`), or a lock on the piece row.
- For the property: a randomised spec (a few hundred random candidate lists) asserting total volume never exceeds capacity.

**Weak signals**

- Starts coding the algorithm before asking what "good" means.
- Duplicates the stage and temperature checks in the planner.
- Tries to be optimal (brute force over subsets) without noticing the cost.

**QA prompts:** empty waiting list, one piece bigger than the whole kiln, every piece from one member, a kiln already full, pieces at exactly the tolerance edge (1230C and 1250C for a 1240C firing), accepting a suggestion after one of its pieces was loaded elsewhere.

</details>

---

## Scorecard

Score 1-4 on each, and write one sentence of evidence for each score.

| | What to look for |
|---|---|
| **Understands before changing** | Reads the code and the specs, runs them, asks about intent, restates the problem |
| **Works in small safe steps** | Green specs between steps, one change at a time, can stop at any point with working code |
| **Tests** | Writes the failing test first or right after, tests behaviour not implementation, covers the edge the QA voice raised |
| **Rails fluency** | Idiomatic ActiveRecord, knows the query it generates, knows where Rails helps and where it hides things |
| **Correctness under pressure** | Money, time zones, concurrency, idempotency: spots at least one without being led |
| **Communication** | Thinks out loud, says what he's unsure of, pushes back with reasons, asks for help when stuck |
| **Uses AI well** | Uses it for typing, not thinking; reads what it wrote; can explain every line at the no-AI checkpoint |

Two questions to end every session with, in the CTO voice:

1. "If you had another hour, what would you do next and why?"
2. "What would you want to know about our codebase before you started on a ticket like this for real?"
