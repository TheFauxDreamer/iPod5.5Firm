# Rules for this project

## Writing style: ASD-STE100 Simplified Technical English

This rule is mandatory. Write all text in ASD-STE100 Simplified Technical English. The rule applies to:

- documents in `docs/` and `re/`, and the READMEs;
- code comments in Swift, Python, C, Java and shell scripts;
- text in the user interface of the iPodFirm app, and error messages;
- `patch.json` descriptions and warnings;
- commit messages and pull request descriptions;
- remarks to the owner.

The rule applies unless the owner explicitly gives a different instruction. When you change old text that does not obey the rule, write it again in STE.

Apply these rules:

- Write a procedural sentence with a maximum of 20 words.
- Write a descriptive sentence with a maximum of 25 words.
- Write only one instruction in each sentence.
- Use the imperative for instructions. Example: "Connect the iPod."
- Use the active voice.
- Use the simple tenses: present, simple past and simple future.
- Use simple words that have only one meaning.
- Use the same term for the same item each time.
- Do not use phrasal verbs, idioms, slang or contractions.
- Use the articles "the" and "a" where possible.
- Do not use words that end in "-ing" as nouns or as verbs if an alternative is available.
- Write paragraphs that have only one topic and a maximum of six sentences.
- Use vertical lists for steps and for sequences.
- Put a warning or a caution before the instruction that it applies to.

Do not change code identifiers, command names, file names or program output.

## Documents must agree with the code

This rule is mandatory. Each change to the code must update the documents that it affects.

1. Before you complete a change, find the affected documents in the table "Keep the reference current" in [docs/README.md](docs/README.md).
2. Update each affected document in the same commit as the code.
3. Measure each value that you write, for example a patch size, an address or a hook value. Do not copy an old value.
4. Record each new Ghidra or emulator result in `re/` first. Then copy the result into `docs/firmware-functions.md`.
5. Update the test status in `docs/safety.md` and `docs/modifications.md` after each test on the real iPod.

If the code and a document do not agree, the code is correct. Correct the document.

## Everything stays local

This rule is mandatory. Never publish a document, a page, a report or any other file to a web service. This includes claude.ai Artifacts and Claude Docs.

- Write documents as Markdown files in `docs/` or `re/`.
- Write a page for other people as one self-contained `.html` file in the repository. Put all CSS and JavaScript in the file. Do not load fonts, scripts or styles from the internet.
- The owner shares the files.

## Other rules

- Each feature that operates on the iPod or on the firmware must have a user interface in the iPodFirm app. A command-line tool alone is not sufficient.
- Each build of the iPodFirm app must increase the version number and the build number. `mac/scripts/build-app.sh` does this.
- Give each new patch a `version_letter` in its `patch.json`. Use one letter a–z that no other patch uses. An `internal` patch does not get a letter. The test `testPatchVersionLetters` makes sure of this.
- Do not commit Apple firmware files, `.ipsw` files or iPod backups.
