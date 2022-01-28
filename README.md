# Fatpub

A Pandoc preprocessor that enables authors to write books in Markdown/Markua although their old-fashioned publishers expect DOC(X) files.

Can be useful in the following cases:

* You’ve published a book on [Leanpub](https://leanpub.com) and now want to move on to a traditional publisher like Pearson/Addison-Wesley or dpunkt.
* You’re writing a new book with a publisher that requires you to provide the manuscript in DOC(X) but want to write in Markdown nontheless.

It works as a converter from Markua/Markdown to the publishers specific DOCX template styling.
Outputs a Markdown file ready as input for Pandoc.

## The Publisher Template

Your publisher will provide you with a DOC or DOCX file. It will have a strange name like `ptg_awph02.dot`. If it is in DOC format (not DOCX format) then first open the template file and save it in DOCX format, since Pandoc won't accept DOC.

Currently the following templates (that you will get from your publisher) are supported:

* Addison-Wesley/Pearson: `ptg_awph02`
* dpunkt: `dpunkt_einspaltig` and `dpunkt_2019`

## Usage

### As GitHub Action

If you're writing your book on GitHub (and especially when you started on Leanpub) then this is probably the easiest way.
Add a file `.github/build-docx.yml` to your repository and add the following content. Change the template parameters in that content. That is `template` in the Fatpub action and `--reference-doc` in the Pandoc action.

```yaml
name: Generate book as DOCX file
on:
  - push

jobs:
  build-docx:
    runs-on: ubuntu-20.04
    steps:

      - name: Checkout
        uses: actions/checkout@v2
    
      - name: Convert to Publisher format
        uses: hschwentner/fatpub@1.5
        with:
          template: ptg_awph02 # alternatives: dpunkt_einspaltig dpunkt_2019
          in: manuscript/book.txt 
          out: book-with-publisher-styles.md

      - name: Convert MD to DOCX
        uses: docker://pandoc/core:2.17.0.1
        with:  # alternatives: dpunkt_einspaltig.docx Vorlage-2019.dotx
          args: >
            --fail-if-warnings
            --resource-path=manuscript
            --reference-doc=ptg_awph02.dotx
            --output=book.docx
            book-with-publisher-styles.md
      
      - uses: actions/upload-artifact@v2
        with:
          name: book
          path: book.docx
```

Commit and push to GitHub. Now go to the books project page on GitHub and click on 'Actions'. There you should see a build running. If everything goes well, you will end up with a DOCX file of your book :-)

## Standalone

If you’re not on GitHub you can run Fatpub and Pandoc on your own machine.

### Prerequisites

* Perl
* [Pandoc](https://pandoc.org)

### Installation

Clone the Fatpub repository. The executables are in the directory `bin`.
To see the possible options run Fatpub with the help option:

```fish
bin/fatpub --help
```

### Conversion

If your book is in a single file `anna_karenina.md` and the template in `ptg_awph02_main.docx`, you would convert it like this:

```fish
fatpub --template ptg_awph02 --output anna_karenina_aw.md --single-file anna_karenina.md
pandoc --reference-doc=ptg_awph02_main.docx anna_karenina_aw.md
```

If you’ve written your book on Leanpub you will have a file for every chapter which are all listed in file with the name `book.txt` or similar. In this case you would convert it like this:

```fish
fatpub --template ptg_awph02 --output book_aw.md manuscript/book.txt
pandoc --reference-doc=ptg_awph02_main.docx book_aw.md
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

This script was created writing the book *Domain Storytelling* with Pearson. I hope it will help other authors as well. Please [get in touch with me](https://hschwentner.io)!
