# Rules for this project

## Writing style: ASD-STE100 Simplified Technical English

Write all documents, code comments, READMEs and remarks in ASD-STE100 Simplified Technical English. This rule applies unless the owner explicitly gives a different instruction.

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

## Other rules

- Each feature that operates on the iPod or on the firmware must have a user interface in the iPodFirm app. A command-line tool alone is not sufficient.
- Each build of the iPodFirm app must increase the version number and the build number. `mac/scripts/build-app.sh` does this.
- Do not commit Apple firmware files, `.ipsw` files or iPod backups.
