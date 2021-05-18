# markua2aw
A converter from Markua/Markdown to Addison-Wesley's specific DOCX styling.
Outputs a Markdown file ready as input for Pandoc.
Useful for authors that:

* publish with Pearson and want to write their text in Markdown or
* first publish a book on LeanPub and then move on to Pearson/Addison-Wesley.

## Prerequisites

* Perl
* Pandoc
* The template DOC files from Pearson

First open the template files and save them in DOCX format, since Pandoc won't accept DOC.

## Usage

If your book is in a file `anna_karenina.md` and the template in `ptg_awph02_main.docx`, you would convert it like this:

```fish
markua2aw anna_karenina.md > anna_karenina_aw.md
pandoc --from commonmark_x --to docx --reference-doc=ptg_awph02_main.docx anna_karenina_aw.md
```

or as a one-liner:

```fish
markua2aw anna_karenina.md | pandoc --from commonmark_x --to docx --reference-doc=ptg_awph02_main.docx --output anna_karenina.docx anna_karenina.md
```

## Extensions to Markdown/Markua

Besides the standard Markua markup, the script supports some AW specific things.

### Dialog

Four asterisks and a colon are used to markup dialog between several speakers. Quotation marks are possible but not required.

```markdown
****Fabienne:**** "Whose motorcycle is this?"

****Butch:**** "It’s a chopper, baby."

****Fabienne:**** "Whose chopper is this?"

****Butch:**** "It's Zed's."

****Fabienne:**** "Who's Zed?"

****Butch:**** "Zed's dead, baby. Zed's dead..."
```

## Contact

This script was created writing the book *Domain Storytelling*. I hope it will help other authors as well. Please get in touch with me!
