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

## Examine new files before each commit

This rule is mandatory. Before you make a commit, examine each new file and each changed file in the commit.

1. Make sure that the hook is on. Run `git config core.hooksPath .githooks` in each new clone.
2. Read the new text. Make sure that it has no absolute path and no private data, for example a real name, an e-mail address, a key or a token.
3. Use relative paths in scripts. Example: `Path(__file__).resolve().parents[3]`.
4. Make sure that the commit has no Apple firmware, no `.ipsw` file, no iPod backup, no key file and no music file.
5. Make sure that no file is larger than 5 MB.
6. If the hook `.githooks/pre-commit` stops the commit, correct the problem. Then make the commit again.

The workflow `.github/workflows/repository-check.yml` runs `.githooks/check-repository` at each push. Keep the two scripts in agreement.

Do not use `git commit --no-verify` unless the owner tells you to do it.

## Do not close the running app

This rule is mandatory. The owner can start a flash at any time. If the app closes during a flash, the iPod can get a partial firmware.

- Never quit or stop an iPodFirm app, or a copy with a different name, unless the owner tells you to do it.
- Before you run `mac/scripts/build-app.sh`, examine if the app is open. Use `pgrep -f "/Applications/iPodFirm"`.
- If the app is open, tell the owner and wait. Do not start the build.
- `mac/scripts/build-app.sh` does not quit the app. It waits, and then it stops with an error. Keep this behaviour.

## Other rules

- Each feature that operates on the iPod or on the firmware must have a user interface in the iPodFirm app. A command-line tool alone is not sufficient.
- Each build of the iPodFirm app must increase the version number and the build number. `mac/scripts/build-app.sh` does this.
- Give each new patch a `version_letter` in its `patch.json`. Use one letter a–z that no other patch uses. An `internal` patch does not get a letter. The test `testPatchVersionLetters` makes sure of this.
- Give each patch a `version` in its `patch.json`, for example `"1.0"`. Use one to three numbers with dots. The test `testPatchVersions` makes sure of this.
- Increase the `version` of a patch at each change to its `patch.json` or its code. Then the install sheet shows the new file as an update.
- Record the size of each patch on the iPod in its `patch.json`, for example `"size": 3080`. This includes `internal` patches such as `dark-mode`. Measure the value. Do not estimate it. The test `testPatchSizes` makes sure of this.
- Update `"size"` at each change to the code of a patch. A patch with no code has `"size": 0`.
- An installed patch must also have a correct size. The install and **Export Patch…** write the measured size into `patch.json` if the value is missing or wrong. At the start, the app records the size of each installed patch that has no size. Keep this behaviour.
- The app shows the size of each patch and of the dark theme in the Patches pane. Each new item that adds data to the firmware must also show its size there.
- Do not commit Apple firmware files, `.ipsw` files or iPod backups.
- Thank each person who reports a problem, supplies a fix, tests a fix or gives an idea that goes into the app. Do this in the same commit as the change:
  1. Add an entry to `Thanks.people` in `mac/Sources/IPodFWKit/Thanks.swift`. The app shows the list in Help > Thanks….
  2. Set `version` to the first app version that has the change. Use the version that `mac/scripts/build-app.sh` gives for the build.
  3. If the person already has an entry, update the reason and the `version`. Do not add a second entry.
  4. Add the person to the Credits section of `README.md`.

  The tests `testThanksSortNewestFirst` and `testThanksEntries` make sure of steps 2 to 4.
