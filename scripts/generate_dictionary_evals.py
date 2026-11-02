#!/usr/bin/env python3
"""Generate the dictionary evaluation corpora from vocab_v4.json."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOCAB = ROOT / "Packages/L2-Engines/catalog/vocab_v4.json"
RESOURCES = ROOT / "Packages/L2-Engines/TextPipeline/Tests/TextPipelineTests/Resources"


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9']+", text.lower())


def contained(candidate: str, aliases: list[str]) -> bool:
    needle = " " + " ".join(words(candidate)) + " "
    for alias in aliases:
        if alias == candidate:
            continue
        if needle in " " + " ".join(words(alias)) + " ":
            return True
    return False


def main() -> int:
    data = json.loads(VOCAB.read_text(encoding="utf-8"))
    entries = data["entries"]
    RESOURCES.mkdir(parents=True, exist_ok=True)

    nouns = [
        "the laundry", "the dishes", "the report", "the letter", "the email",
        "the garden", "the car", "the kitchen", "the floor", "the windows",
        "the curtains", "the groceries", "the room", "the table", "the chairs",
        "the sofa", "the bed", "the door", "the hallway", "the balcony",
    ]
    places = [
        "the park", "the store", "the office", "the beach", "the museum",
        "the library", "the station", "the market", "the garden", "the airport",
        "the river", "the mountain", "the coast", "the village", "the city",
        "the farm", "the lake", "the forest", "the island", "the valley",
    ]
    names = [
        "Jason", "Alice", "Bob", "Maria", "Chen", "Priya", "Omar", "Sofia",
        "Liam", "Noah", "Emma", "Olivia", "Mateo", "Ava", "Ethan", "Mia",
        "Lucas", "Zara", "Hugo", "Nina",
    ]
    templates = [
        "Let's do it next year at {place}.",
        "The cloud over {place} is cheap today.",
        "Take a quick look at {noun}.",
        "View {noun} from {place}.",
        "{name} called me from {place}.",
        "I go to {place}.",
        "Render the fat slowly in {noun}.",
        "The queen arrived at {place}.",
        "Tech stocks fell after the news from {place}.",
        "Spring is here at {place}.",
        "It's drizzling outside {place}.",
        "Move the cursor to the left of {noun}.",
        "The oath of office was long at {place}.",
        "Jot this down on {noun}.",
        "We flew to Tokyo from {place}.",
        "The sequel was better than {noun}.",
        "Dry {noun} before {place}.",
        "That's a solid plan for {place}.",
        "Express delivery arrived at {place}.",
        "There is a node in the graph near {place}.",
    ]
    negatives: list[str] = []
    for index, template in enumerate(templates):
        for offset in range(15):
            sentence = template.format(noun=nouns[(index + offset) % len(nouns)],
                                       place=places[(index * 3 + offset) % len(places)],
                                       name=names[(index + offset) % len(names)])
            negatives.append(sentence)
    # Explicit gated false-positive checks.
    negatives += [
        "Use textract to parse the PDF.",
        "AWS Textract can read the scanned document.",
        "Cloud storage is cheap.",
        "Cloud code is a Google product.",
        "The cursor is a blinking line.",
        "A node in the graph has no children.",
        "The dry cleaner lost my shirt.",
        "The spring in the mattress broke.",
        "A quick fox jumped over the fence.",
        "Jason's report is on the table.",
        "The queen's oath was long.",
        "Render the image at full resolution.",
    ]
    negatives = list(dict.fromkeys(negatives))[:320]
    (RESOURCES / "negatives.txt").write_text("\n".join(negatives) + "\n", encoding="utf-8")

    aliases: list[str] = []
    for entry in entries:
        for alias in entry["aliases"]:
            aliases.append(alias["t"])

    positives: list[str] = []
    for entry in entries:
        canonical = entry["canonical"]
        for alias in entry["aliases"]:
            if alias["tier"] != "A":
                continue
            text = alias["t"]
            if "\t" in text or "\n" in text or len(words(text)) == 0:
                continue
            if contained(text, aliases):
                continue
            sentence = f"the team uses {text} for the current task"
            expected = sentence.replace(text, canonical, 1)
            if sentence != expected:
                positives.append(f"{sentence}\t{expected}")
    positives = list(dict.fromkeys(positives))[:320]
    positives += [
        "go build the binary\tGo build the binary",
        "next year we should use next js\tnext year we should use Next.js",
        "the cloud model is expensive\tthe Claude model is expensive",
        "use cursor to edit the file\tuse Cursor to edit the file",
        "jason parse the config\tJSON parse the config",
        "textract for the tech stack\ttech stack for the tech stack",
        "tan stack query\tTanStack Query",
        "next jay ess app router\tNext.js app router",
        "claude code hooks\tClaude Code hooks",
    ]
    (RESOURCES / "positives.txt").write_text("\n".join(positives) + "\n", encoding="utf-8")
    print(f"negatives: {len(negatives)}, positives: {len(positives)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
