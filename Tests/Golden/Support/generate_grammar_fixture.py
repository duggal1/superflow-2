#!/usr/bin/env python3
"""Generate the reviewed grammar golden corpus.

The corpus is deterministic: running this script rewrites
Tests/Golden/Tests/GoldenTests/Fixtures/grammar/cases.json byte-for-byte.
Review the diff before committing a change; `scripts/golden-update.sh`
runs this generator and then the golden suite.

Corpus shape (PLAN.md section 11): about 200 dictation-style sentences with
expected outputs, 50 per enabled lint category, plus decoys that the gate must
reject (protected span, no-op suggestion, disallowed kind, overlap, bad range,
missing suggestion).
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "Tests/Golden/Tests/GoldenTests/Fixtures/grammar/cases.json"

# (misspelled, correct, sentence)
SPELLING = [
    ("recieve", "receive", "I recieve the quarterly report before the meeting starts."),
    ("teh", "the", "Please send teh draft to the design team this afternoon."),
    ("definately", "definitely", "We should definately review the numbers before Friday."),
    ("seperate", "separate", "Can you seperate the invoices from the receipts please."),
    ("occured", "occurred", "The outage occured right after the deployment finished."),
    ("adress", "address", "I need the adress for the new office in Brooklyn."),
    ("beleive", "believe", "I beleive the client wants a shorter summary this time."),
    ("accomodate", "accommodate", "We can accomodate eight people in the small room."),
    ("wich", "which", "Let me know wich option works better for your schedule."),
    ("thier", "their", "The engineers finished thier review late last night."),
    ("alot", "a lot", "That change will save us alot of time next quarter."),
    ("untill", "until", "Keep the branch open untill the tests are green."),
    ("begining", "beginning", "The begining of the document needs a clearer summary."),
    ("calender", "calendar", "Add the launch review to my calender for Thursday."),
    ("commited", "committed", "The team commited to shipping the fix this week."),
    ("concious", "conscious", "I am concious of the risk and I accept it for now."),
    ("existance", "existence", "Nobody questioned the existance of the backup file."),
    ("foriegn", "foreign", "The foriegn exchange rate moved again this morning."),
    ("goverment", "government", "The goverment published new accessibility guidance today."),
    ("immediatly", "immediately", "Please call me immediatly if the build fails again."),
    ("independant", "independent", "We hired an independant reviewer for the security audit."),
    ("knowlege", "knowledge", "Her knowlege of the codebase saved us a full day."),
    ("maintainance", "maintenance", "The maintainance window starts at midnight on Saturday."),
    ("neccessary", "necessary", "Is it neccessary to restart the service after the change."),
    ("occassion", "occasion", "We only use the large room on a special occassion."),
    ("persistant", "persistent", "That persistant warning finally disappeared after the update."),
    ("priviledge", "privilege", "It was a priviledge to work with the original author."),
    ("reccomend", "recommend", "I reccomend we start with the smaller experiment first."),
    ("refered", "referred", "The support team refered the case to our group."),
    ("succesful", "successful", "The migration was succesful and no rows were lost."),
    ("tommorow", "tomorrow", "Let us plan to meet tommorow at nine in the morning."),
    ("truely", "truly", "The new search is truely faster than the old one."),
    ("wierd", "weird", "It felt wierd to see the dashboard without any data."),
    ("writting", "writing", "I am writting a short note for the release announcement."),
    ("arguement", "argument", "That arguement convinced everyone in the room."),
    ("basicly", "basically", "The tool basicly does the same thing with fewer clicks."),
    ("completly", "completely", "The cache was completly empty after the restart."),
    ("diffrent", "different", "We need a diffrent approach for the offline case."),
    ("enviroment", "environment", "The staging enviroment matches production closely now."),
    ("familar", "familiar", "That error message looks familar from last month."),
    ("finaly", "finally", "The backup finaly finished after twenty minutes."),
    ("garantee", "guarantee", "I cannot garantee the same latency under load."),
    ("happend", "happened", "Nothing happend after I clicked the refresh button."),
    ("intresting", "interesting", "That is an intresting edge case for the parser."),
    ("langauge", "language", "The langauge setting resets whenever the app restarts."),
    ("managment", "management", "The managment team approved the new hiring plan."),
    ("oppurtunity", "opportunity", "This is a good oppurtunity to simplify the module."),
    ("posible", "possible", "It is not posible to undo that change from the UI."),
    ("questionaire", "questionnaire", "Please fill out the questionaire before the workshop."),
    ("responsibilty", "responsibility", "Ownership of the release is my responsibilty this month."),
]

# (find, replace, sentence)
AGREEMENT = [
    ("are", "is", "The list of pending items are on the shared drive."),
    ("are", "is", "One of the configuration files are missing from the bundle."),
    ("are", "is", "Each of the proposed options are expensive to maintain."),
    ("are", "is", "The team are ready to present the results on Monday."),
    ("is", "are", "There is many reasons to keep the old endpoint for now."),
    ("don't", "doesn't", "He don't want to change the schema before the freeze."),
    ("was", "were", "They was planning to migrate the database last weekend."),
    ("have", "has", "She have already reviewed the pull request twice."),
    ("are", "is", "The news about the delay are spreading across the office."),
    ("were", "was", "The number of failed jobs were lower than expected."),
    ("are", "is", "A variety of templates are available in the gallery."),
    ("is", "are", "The rest of the documents is stored in the archive."),
    ("has", "have", "My colleagues has agreed to help with the rollout."),
    ("are", "is", "Neither of the two servers are responding to pings."),
    ("was", "were", "The engineers was debugging the race condition all night."),
    ("are", "is", "The collection of samples are organized by session."),
    ("does", "do", "The support team does not answer calls after six."),
    ("were", "was", "A small group of users were affected by the outage."),
    ("are", "is", "The quality of the recordings are improving every week."),
    ("have", "has", "The product manager have signed off on the design."),
    ("is", "are", "There is several open questions about the migration."),
    ("are", "is", "The set of required permissions are listed below."),
    ("don't", "doesn't", "The script don't clean up temporary files by default."),
    ("was", "were", "The reviewers was impressed by the simpler approach."),
    ("are", "is", "The cost of the new machines are higher this year."),
    ("have", "has", "The documentation have not been updated since March."),
    ("are", "is", "The group of volunteers are meeting on Thursday."),
    ("is", "are", "The remaining tasks is tracked in the project board."),
    ("were", "was", "The series of tests were green before the merge."),
    ("has", "have", "The two reviewers has different opinions about the name."),
    ("are", "is", "The majority of the feedback are positive so far."),
    ("was", "were", "The list of attendees was updated after lunch."),
    ("are", "is", "The contents of the folder are backed up nightly."),
    ("do", "does", "The API client do not retry failed requests yet."),
    ("have", "has", "The committee have decided to postpone the launch."),
    ("are", "is", "The scope of these changes are still being discussed."),
    ("were", "was", "The batch of imports were processed without errors."),
    ("is", "are", "The results from both experiments is consistent."),
    ("has", "have", "The design and the copy has to be reviewed together."),
    ("are", "is", "The total number of downloads are shown on the dashboard."),
    ("was", "were", "The pages in the report was missing page numbers."),
    ("don't", "doesn't", "The scheduler don't run on public holidays."),
    ("are", "is", "The stack of printed notes are sitting on my desk."),
    ("have", "has", "The owner of these repositories have moved teams."),
    ("is", "are", "The instructions for the workshop is in the shared folder."),
    ("were", "was", "The pair of headphones were left in the conference room."),
    ("are", "is", "The amount of noise in the recording are too high."),
    ("do", "does", "The main process do not restart after a crash."),
    ("has", "have", "The people on the call has already seen the demo."),
    ("are", "is", "The summary of the findings are attached to this email."),
]

# (find, replace, sentence)
REPEATED = [
    ("the the", "the", "Please close the the window before you leave."),
    ("and and", "and", "We need the budget and and the approval by Friday."),
    ("to to", "to", "I want to to review the plan one more time."),
    ("is is", "is", "The main issue is is the missing migration file."),
    ("we we", "we", "Yesterday we we decided to postpone the release."),
    ("that that", "that", "I think that that change is too risky for now."),
    ("a a", "a", "She asked for a a copy of the signed contract."),
    ("of of", "of", "The end of of the document is still blank."),
    ("in in", "in", "The keys are stored in in the shared vault."),
    ("it it", "it", "If it it fails again we should roll back."),
    ("for for", "for", "This is for for the internal review only."),
    ("on on", "on", "The notes are on on the second page."),
    ("with with", "with", "Let us start with with the smallest task."),
    ("be be", "be", "The build should be be reproducible from scratch."),
    ("at at", "at", "Meet me at at the front desk at noon."),
    ("this this", "this", "I have seen this this error in the logs before."),
    ("from from", "from", "The data came from from the legacy system."),
    ("by by", "by", "The report was written by by the research team."),
    ("or or", "or", "We can ship it today or or wait for the review."),
    ("as as", "as", "Use the same name as as the old service."),
    ("you you", "you", "I think you you already know the answer."),
    ("can can", "can", "We can can revisit the decision next month."),
    ("will will", "will", "The client will will send the files tomorrow."),
    ("have have", "have", "I have have seen this pattern many times."),
    ("not not", "not", "Please do not not share the link outside the team."),
    ("are are", "are", "The tests are are running on the new machine."),
    ("was was", "was", "The first attempt was was much slower than this."),
    ("but but", "but", "I agree but but we still need a second opinion."),
    ("so so", "so", "The room was full so so we moved to the hall."),
    ("if if", "if", "Let me know if if the schedule changes."),
    ("an an", "an", "That was an an unexpected result for everyone."),
    ("my my", "my", "Please check my my calendar for the exact time."),
    ("your your", "your", "I will send your your access badge by courier."),
    ("there there", "there", "I think there there is a simpler way to do this."),
    ("what what", "what", "I am not sure what what they meant by that."),
    ("when when", "when", "Call me when when the migration is finished."),
    ("who who", "who", "The person who who reported it is on holiday."),
    ("how how", "how", "We should ask how how they measured the latency."),
    ("all all", "all", "In fact all all of the tickets are now closed."),
    ("up up", "up", "Please back up up the database before the upgrade."),
    ("out out", "out", "The old cache was cleared out out last week."),
    ("very very", "very", "That was a very very long meeting."),
    ("just just", "just", "I just just need five more minutes."),
    ("also also", "also", "The update also also fixes the export bug."),
    ("more more", "more", "We need more more detail in the error message."),
    ("then then", "then", "Save the file then then run the tests."),
    ("because because", "because", "It failed because because the token expired."),
    ("only only", "only", "There is only only one environment left."),
    ("one one", "one", "Only one one person has access to that account."),
    ("like like", "like", "It looks like like the same problem as before."),
]

# (find, replace, sentence)
A_OR_AN = [
    ("a apple", "an apple", "I ate a apple with breakfast this morning."),
    ("an report", "a report", "She sent an report to the leadership team."),
    ("a hour", "an hour", "The call took a hour longer than planned."),
    ("an user", "a user", "I saw an user report the same issue twice today."),
    ("a honest", "an honest", "He gave a honest answer during the review."),
    ("a update", "an update", "We shipped a update to the beta channel."),
    ("a idea", "an idea", "That is a idea worth testing next sprint."),
    ("an meeting", "a meeting", "I have an meeting with the design team at two."),
    ("a email", "an email", "Please send a email when the build is ready."),
    ("an test", "a test", "We need an test that covers the retry path."),
    ("a hour", "an hour", "Give me a hour to finish the draft."),
    ("an project", "a project", "They started an project to simplify onboarding."),
    ("a offer", "an offer", "The vendor made a offer we could refuse."),
    ("an change", "a change", "That is an change I would support."),
    ("a event", "an event", "We are hosting a event for the local community."),
    ("an bug", "a bug", "I found an bug in the export flow."),
    ("a issue", "an issue", "There is a issue with the search index."),
    ("an ticket", "a ticket", "Please open an ticket for the flaky test."),
    ("a example", "an example", "Can you add a example to the documentation."),
    ("an request", "a request", "I sent an request to the billing team."),
    ("a answer", "an answer", "We finally have a answer to that question."),
    ("an plan", "a plan", "They proposed an plan with three phases."),
    ("a hour", "an hour", "The backup runs every a hour in staging."),
    ("an model", "a model", "We trained an model on the new dataset."),
    ("a invoice", "an invoice", "The finance team sent a invoice this morning."),
    ("an release", "a release", "We cut an release every other Thursday."),
    ("a API", "an API", "The client needs a API for bulk imports."),
    ("an file", "a file", "Please attach an file with the sample rows."),
    ("a iPhone", "an iPhone", "She tested the flow on a iPhone before launch."),
    ("an URL", "a URL", "The error message includes an URL to the docs."),
    ("a SDK", "an SDK", "They published a SDK for the new endpoint."),
    ("a item", "an item", "We removed a item from the checklist."),
    ("a option", "an option", "There is a option to export as CSV."),
    ("an table", "a table", "The migration created an table with the old rows."),
    ("a exception", "an exception", "The handler threw a exception during shutdown."),
    ("an script", "a script", "I wrote an script to rotate the logs."),
    ("a entry", "an entry", "Each request adds a entry to the audit log."),
    ("a alert", "an alert", "We received a alert about the elevated latency."),
    ("a environment", "an environment", "They created a environment for the demo."),
    ("a account", "an account", "The new hire needs a account by Monday."),
    ("a object", "an object", "The parser returned a object with two fields."),
    ("a image", "an image", "The build includes a image for the splash screen."),
    ("a event", "an event", "The logger records a event for every retry."),
    ("a order", "an order", "The customer placed a order for two licenses."),
    ("a item", "an item", "We need a item that explains the pricing."),
    ("a answer", "an answer", "That is a answer I did not expect."),
    ("a hour", "an hour", "The interview is a hour and a half long."),
    ("an unit", "a unit", "We added an unit test for the parser."),
    ("a iPad", "an iPad", "The layout looks fine on a iPad in landscape."),
    ("an member", "a member", "I heard an member of the team raise the concern."),
]

DECOYS = [
    {
        "name": "decoy protected dictionary word",
        "category": "spelling",
        "input": "The Superflow release notes are ready for review.",
        "protectedLiterals": ["Superflow"],
        "lints": [{"find": "Superflow", "replace": "Super flow", "kind": "spelling"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy protected url",
        "category": "spelling",
        "input": "Open https://example.com/recieve and check the response.",
        "lints": [{"find": "recieve", "replace": "receive", "kind": "spelling"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy protected email",
        "category": "spelling",
        "input": "Send the note to recieve@example.com before lunch.",
        "lints": [{"find": "recieve", "replace": "receive", "kind": "spelling"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy no-op suggestion",
        "category": "agreement",
        "input": "The list of files is ready for the review.",
        "lints": [{"find": "is", "replace": "is", "kind": "agreement"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy disallowed style kind",
        "category": "agreement",
        "input": "The team is ready to present the plan.",
        "lints": [{"find": "ready", "replace": "prepared", "kind": "style"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy disallowed word choice kind",
        "category": "spelling",
        "input": "We should utilize the existing pipeline.",
        "lints": [{"find": "utilize", "replace": "use", "kind": "wordChoice"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy missing suggestion",
        "category": "spelling",
        "input": "I recieve the report every Monday.",
        "lints": [{"find": "recieve", "kind": "spelling"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy zero length range",
        "category": "spelling",
        "input": "I recieve the report every Monday.",
        "lints": [{"utf16Start": 2, "utf16Length": 0, "replace": "receive", "kind": "spelling"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy out of range",
        "category": "spelling",
        "input": "I recieve the report every Monday.",
        "lints": [{"utf16Start": 500, "utf16Length": 7, "replace": "receive", "kind": "spelling"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy negative range",
        "category": "spelling",
        "input": "I recieve the report every Monday.",
        "lints": [{"utf16Start": -1, "utf16Length": 7, "replace": "receive", "kind": "spelling"}],
        "expectedAccepted": [],
    },
    {
        "name": "decoy overlapping second edit",
        "category": "spelling",
        "input": "I recieve teh report every Monday.",
        "lints": [
            {"find": "recieve", "replace": "receive", "kind": "spelling"},
            {"find": "recieve teh", "replace": "received the", "kind": "spelling"},
        ],
        "expectedAccepted": [0],
    },
    {
        "name": "decoy repeated word inside protected term",
        "category": "repeatedWords",
        "input": "The Superflow Superflow dashboard is open.",
        "protectedLiterals": ["Superflow Superflow"],
        "lints": [{"find": "Superflow Superflow", "replace": "Superflow", "kind": "repeatedWords"}],
        "expectedAccepted": [],
    },
    {
        "name": "protected code token does not block a distant aOrAn edit",
        "category": "aOrAn",
        "input": "Set a apple as the default in config.yaml.",
        "protectedLiterals": ["config.yaml"],
        "lints": [{"find": "a apple", "replace": "an apple", "kind": "aOrAn"}],
        "expectedAccepted": [0],
    },
    {
        "name": "emoji offsets are utf16",
        "category": "spelling",
        "input": "Ship it \U0001F680 recieve the notes after.",
        "lints": [{"utf16Start": 11, "utf16Length": 7, "replace": "receive", "kind": "spelling"}],
        "expectedAccepted": [0],
        "expectedFinal": "Ship it \U0001F680 receive the notes after.",
    },
    {
        "name": "CJK offsets are utf16",
        "category": "spelling",
        "input": "\u4f60\u597d recieve the notes.",
        "lints": [{"utf16Start": 3, "utf16Length": 7, "replace": "receive", "kind": "spelling"}],
        "expectedAccepted": [0],
        "expectedFinal": "\u4f60\u597d receive the notes.",
    },
    {
        "name": "decoy second edit after first edit",
        "category": "agreement",
        "input": "The list of files are ready and the team are waiting.",
        "lints": [
            {"find": "are", "replace": "is", "kind": "agreement"},
            {"find": "are", "replace": "is", "kind": "agreement"},
        ],
        "expectedAccepted": [0],
    },
]


def is_word_char(char: str) -> bool:
    return char.isalnum() or char == "_"


def find_word(text: str, needle: str) -> int:
    """First whole-word occurrence, matching the Swift fixture locator."""
    start = 0
    while True:
        index = text.find(needle, start)
        if index < 0:
            return -1
        before = text[index - 1] if index > 0 else ""
        after_index = index + len(needle)
        after = text[after_index] if after_index < len(text) else ""
        if (not before or not is_word_char(before)) and (not after or not is_word_char(after)):
            return index
        start = index + 1


def replace_once(text: str, find: str, replacement: str) -> str:
    index = find_word(text, find)
    if index < 0:
        raise SystemExit(f"missing find text {find!r} in {text!r}")
    if find_word(text[index + 1:], find) >= 0:
        raise SystemExit(f"find text {find!r} is not unique in {text!r}")
    return text[:index] + replacement + text[index + len(find):]


def build_cases(items, category, kind):
    cases = []
    for index, (find, replacement, sentence) in enumerate(items, start=1):
        cases.append({
            "name": f"{category}-{index:02d}",
            "category": category,
            "input": sentence,
            "lints": [{"find": find, "replace": replacement, "kind": kind}],
            "expectedAccepted": [0],
            "expectedFinal": replace_once(sentence, find, replacement),
        })
    return cases


def apply_expected(case):
    if "expectedFinal" in case:
        return case
    text = case["input"]
    for index in sorted(case["expectedAccepted"]):
        lint = case["lints"][index]
        if "find" not in lint:
            raise SystemExit(f"case {case['name']} needs an explicit expectedFinal")
        position = find_word(text, lint["find"])
        if position < 0:
            raise SystemExit(f"case {case['name']} is missing {lint['find']!r}")
        text = text[:position] + lint["replace"] + text[position + len(lint["find"]):]
    case["expectedFinal"] = text
    return case


def main():
    cases = []
    cases += build_cases(SPELLING, "spelling", "spelling")
    cases += build_cases(AGREEMENT, "agreement", "agreement")
    cases += build_cases(REPEATED, "repeatedWords", "repeatedWords")
    cases += build_cases(A_OR_AN, "aOrAn", "aOrAn")
    for decoy in DECOYS:
        cases.append(apply_expected(decoy))

    payload = {
        "policy": {
            "enabled": True,
            "allowedKinds": ["spelling", "agreement", "repeatedWords", "aOrAn"],
            # The corpus measures category precision, not the production 3 percent
            # edit budget; dedicated tests cover the default budget. A single
            # article fix can replace one word with two ("an project" -> "a
            # project"), which is 2/7 words on the shortest sentences, so the
            # corpus budget must sit above 0.29.
            "maxEditRatio": 0.5,
            "timeCapMs": 50,
        },
        "cases": cases,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {len(cases)} grammar cases to {OUT}")


if __name__ == "__main__":
    main()
