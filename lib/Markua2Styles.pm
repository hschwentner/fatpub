# Copyright (C) 2020-2026  Henning Schwentner
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

package Markua2Styles;

use v5.42;
use warnings;
use autodie;

use utf8;                # UTF8 in sourcecode
use open qw/:std :utf8/; # UTF8 in input and output

use Exporter 'import';
our $VERSION = '1.24';
our @EXPORT  = qw(Markua2Styles);

# Usage:
#print Markua2AW($text, %settings, %styles);

our %settings;
our %styles;

sub Markua2Styles {
    my ($text, $ref_to_settings, $ref_to_styles) = @_;
    %settings = %$ref_to_settings;
    %styles = %$ref_to_styles;

    $text = cleanup($text);

    # Index entries are lifted out here and put back as the last step.
    $text = extractIndexEntries($text);

    $text = cleanupGermanAbbreviations($text);

    $text = translateSpecialAsides($text);

    $text = translateFrontmatter($text);
    $text = translateBackmatter($text);

    $text = translateTables($text);
    $text = translateSourceCode($text);
    $text = translateDefinitionLists($text);
    $text = translateBodyText($text);
    $text = translateSubHeadings($text);
    $text = translateFigures($text);
    $text = translateLists($text);

    $text = translateEmphasizement($text);
    $text = translateDomainStorytellingEmphasizement($text);
    
    $text = translateAsides($text);
    
    $text = translatePartText($text);

    $text = translateForewordText($text);
    $text = translatePrefaceText($text);
    $text = translateAcknowledgmentsText($text);
    $text = translateAboutTheAuthorsText($text);

    $text = translateAppendixText($text);
    $text = translateBibliographyText($text);

    # Main headings as last step
    $text = translateLevelOneHeadings($text);

    $text = removeMarkupForStandardStyles($text);

    # Last step: the raw OOXML of an index field contains backticks, which the
    # code and emphasis rules would otherwise take for inline code.
    $text = expandIndexEntries($text);

    return $text;
}

our @indexEntries;

# One index entry. The nested {i:'...'} is what a |see / |seealso reference
# carries, so a plain non-greedy match would stop at the inner brace and leave
# the tail of the entry standing in the text.
our $INDEX_ENTRY = qr{ \{i: (?: [^{}] | \{i: [^{}]* \} )* \} }x;

sub extractIndexEntries {
    my $text = shift;

    @indexEntries = ();
    my $mode = $settings{'index_entries'} // 'drop';

    if ($mode ne 'word_fields') {
        $text =~ s/$INDEX_ENTRY//g;    # Ignore index entries
        return $text;
    }

    # The placeholder stands in for the entry until expandIndexEntries() puts the
    # field in its place. U+E000 is private use, so no manuscript can contain it,
    # and $PARAGRAPH_START accepts it so a paragraph opening with an entry is
    # still recognised as one.
    $text =~ s/($INDEX_ENTRY)/push @indexEntries, $1; "\x{E000}" . $#indexEntries . "\x{E001}"/ge;

    return $text;
}

sub expandIndexEntries {
    my $text = shift;

    return $text unless @indexEntries;

    # Word builds its index from XE fields, so a Markua index entry becomes one.
    # Pandoc passes the raw OOXML through untouched.
    $text =~ s/\x{E000}(\d+)\x{E001}/indexField($indexEntries[$1])/ge;

    return $text;
}

# Markua writes an index entry as {i: term}, where the term may be quoted, may
# name several levels separated by "!" (an escaped "\!" is a literal one), and
# may end in a |see or |seealso reference:
#
#     {i: Ishmael}
#     {i: "Niagara!cataract"}
#     {i: "Strange\!"}
#     {i: "Tennessee|see{i:'silver'}"}
#
# See <https://help.leanpub.com/en/articles/6961502-how-to-create-an-index-in-a-leanpub-book>.
sub parseIndexEntry {
    my $entry = shift;

    $entry =~ s/^\{i:\s*//;
    $entry =~ s/\}$//;
    $entry =~ s/^\s+|\s+$//g;
    $entry =~ s/^"(.*)"$/$1/s or $entry =~ s/^'(.*)'$/$1/s;    # the quotes are optional

    my ($reference, $target) = ('', '');
    if ($entry =~ s/(?<!\\) \| (see(?:also)?) \s* \{i:\s*(.*?)\s*\} \s*$//x) {
        ($reference, $target) = ($1, $2);
        $target =~ s/^"(.*)"$/$1/s or $target =~ s/^'(.*)'$/$1/s;
    }

    return ($entry, $reference, $target);
}

# Markua separates the levels of an entry with "!", Word with ":".
sub indexLevels {
    my $term = shift;

    my @levels = split /(?<!\\)!/, $term, -1;
    for my $level (@levels) {
        $level =~ s/\\!/!/g;                  # resolve Markua's escape

        # Word's field takes plain text, so inline markup cannot come along.
        # A code span opens and closes with a backtick string of equal length,
        # so a term may carry a backtick of its own between doubled ones. The
        # space that separates such a backtick from the fence is not content.
        $level =~ s{(`+)(.+?)\1}{ my $code = $2; $code =~ s/^ (.*) $/$1/s unless $code =~ /^ +$/; $code }ge;
        $level =~ s/\*\*(.+?)\*\*/$1/g;
        $level =~ s/\*(.+?)\*/$1/g;
        $level =~ s/_(.+?)_/$1/g;

        # Word's field syntax: a backslash escapes what follows, a bare quotation
        # mark would end the argument, and a colon would start another level.
        $level =~ s/\\/\\\\/g;
        $level =~ s/"/\\"/g;
        $level =~ s/:/\\:/g;
    }

    return join ':', @levels;
}

sub indexField {
    my $entry = shift;

    my ($term, $reference, $target) = parseIndexEntry($entry);

    my $field = 'XE "' . indexLevels($term) . '"';
    if ($reference) {
        # Word prints the \t text where the page number would go.
        my $label = $reference eq 'see' ? 'See' : 'See also';
        $field .= qq{ \\t "$label } . indexLevels($target) . '"';
    }

    # XML last, because the field ends up in a text node.
    $field =~ s/&/&amp;/g;
    $field =~ s/</&lt;/g;
    $field =~ s/>/&gt;/g;

    return '`<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        . '<w:r><w:instrText xml:space="preserve"> ' . $field . ' </w:instrText></w:r>'
        . '<w:r><w:fldChar w:fldCharType="end"/></w:r>`{=openxml}';
}

sub cleanup {
    my $text = shift;

    $text =~ s/^%%:::(.*)$/:::$1/gm;   # Für Leanpub auskommentiert, für DOCX einkommentieren
    $text =~ s/^%%(.*?)\n//gm;         # Delete Leanpub comments
    $text =~ s{(<!--.*?-->)}{}msg;     # Delete HTML comments
    $text =~ s{ ?\\$}{  }msg;          # Replace escaped line breaks with two spaces (Fix for a bug in Markdown?) 
    $text =~ s/^ *$//gm;               # Lines with only whitespace                                               # Kommentare starten mit ^%%
    $text =~ s/\n\n+\n/\n\n/gm;        # Not more than 2 newlines
    $text =~ s/^\{sample(.*)$//gm;     # Leanpub-Direktiven wie {sample} ausblenden
    $text =~ s/^\{width(.*)$//gm;
    $text =~ s/^\{id(.*)$//gm;

    return $text;
}

sub cleanupGermanAbbreviations {
    my $text = shift;

    $text =~ s/d\.[  ]?h\./d.&#x202f;h./gm;
    $text =~ s/o\.[  ]?ä\./o.&#x202f;ä./gm;
    $text =~ s/o\.[  ]?Ä\./o.&#x202f;Ä./gm;
    $text =~ s/s\.[  ]?u\./s.&#x202f;u./gm;
    $text =~ s/u\.[  ]?a\./u.&#x202f;a./gm;
    $text =~ s/u\.[  ]?ä\./u.&#x202f;ä./gm;
    $text =~ s/u\.[  ]?Ä\./u.&#x202f;Ä./gm;
    $text =~ s/z\.[  ]?B\./z.&#x202f;B./gm;

    return $text;
}

sub translateSpecialAsides {
    my $text = shift;

    $text =~ s{(\n\nA>.*?A>[^\n]*\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> 🌹+.*?> 🌹+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> 🦋+.*?> 🦋+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> (?:🚢🏗️📦)+.*?> (?:🚢🏗️📦)+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> 🎬+.*?> 🎬+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> 💰+.*?> 💰+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> 🚗+.*?> 🚗+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    
    return $text;
}

sub replaceSpecialExtractsWithAsides {
    my $text = shift;

    $text =~ s/A>/>/gm;
    $text =~ s/\n\n> /\n\n\{aside\}\n\n/gm;
    $text =~ s/> (.*)\n\n/$1\n\n\{\/aside\}\n\n/gm;
    $text =~ s/^> //gm;
    $text =~ s/^>$//gm;  # Empty extract lines
    
    return $text;
}

# Has to be called before translateBodyText()
sub translateFrontmatter {
    my $text = shift;

    $text =~ s{(^# Praise for.*?^\{\{newpage\}\})}{replaceWithStylesInPraise($1)}msge;

    return $text;
}

sub replaceWithStylesInPraise {
    my $text = shift;

    # Praise entries
    $text =~ s/^\*(—.*)\*$/::: {custom-style="$styles{'BKFM_PP_AU_NA'}"}\n$1\n:::/gm;
    $text =~ s/^([“A-ZÄÖÜa-z\[\*].*)$/::: {custom-style="$styles{'BKFM_PP'}"}\n$1\n:::/gm;

    return $text;
}

# Has to be called before translateBodyText()
sub translateBackmatter {
    my $text = shift;

    # Glossary entries
    $text =~ s/^\*{2}\[(.*?)\]\{dst-sf\}—\*{2} (.*)$/::: {custom-style="$styles{'BKRM_GLOS_DEF'}"}\n[$1]{custom-style="$styles{'BKRM_GLOS_KT_SCAP'}"}[—]{custom-style="$styles{'BKRM_GLOS_KT'}"}$2\n:::/gm;
    $text =~ s/^\*{2}(.*?—)\*{2} (.*)$/::: {custom-style="$styles{'BKRM_GLOS_DEF'}"}\n[$1]{custom-style="$styles{'BKRM_GLOS_KT'}"}$2\n:::/gm;
    # Bibliography entries
    $text =~ s/\n\*{2}(\[.*?\])\*{2}(?:\s{2})?\n(.*?)\n/\n::: {custom-style="$styles{'BKRM_BIB1'}"}\n$1\n:::\n::: {custom-style="$styles{'BKRM_BIB2'}"}\n$2\n:::\n/gm;

    return $text;
}

our $PARAGRAPH_START = '[\[\*]*[A-ZÄÖÜa-z“„»@\x{E000}]';

# A bare, unnumbered native table caption (`Table: Caption {#tbl:...}`) must stay
# adjacent to its table for pandoc-crossref to recognize it; the generic
# paragraph-wrapping rules below must not swallow it into a styled div first.
our $NATIVE_TABLE_CAPTION = 'Table: .*\{#tbl:';

# Has to be called before translateBodyText(), otherwise the generic
# paragraph-wrapping regex there grabs the term line first
sub translateDefinitionLists {
    my $text = shift;

    # Nested definition lists (indented by two spaces, one level deep) have to
    # be converted first: they get turned into ordinary ::: divs, which the
    # top-level pass below then just passes through unchanged as part of the
    # outer term's definition. They never have children of their own, so they
    # don't need to look out for already-rendered ::: blocks.
    $text = replaceDefinitionListsToFixpoint($text, 2, 'DL_DL_TERM', 'DL_DL_DEF', 'DL_DL_DEF_CON', 0);

    # Definition lists (supports multiple definitions and continuation
    # paragraphs, and passes through any nested ::: divs from the pass above).
    $text = replaceDefinitionListsToFixpoint($text, 0, 'DL_TERM', 'DL_DEF', 'DL_DEF_CON', 1);

    return $text;
}

# A matched definition list consumes the blank line separating it from the
# next one (and, if it swallows a nested block, from the one after that too),
# so consecutive definition lists only match some of them per pass. Applying
# the substitution repeatedly until it stops changing anything converges on
# all of them, regardless of how many are chained together.
sub replaceDefinitionListsToFixpoint {
    my ($text, $indent, $term_style_key, $def_style_key, $def_con_style_key, $allow_children) = @_;

    while (1) {
        my $new_text = replaceDefinitionLists($text, $indent, $term_style_key, $def_style_key, $def_con_style_key, $allow_children);
        last if $new_text eq $text;
        $text = $new_text;
    }

    return $text;
}

sub replaceDefinitionLists {
    my ($text, $indent, $term_style_key, $def_style_key, $def_con_style_key, $allow_children) = @_;
    my $pad = ' ' x $indent;

    # Terms are either normal paragraph starts, numbered terms like
    # "&#x31;. Brainstorming" (an escaped "1." used to avoid Pandoc's
    # automatic numbered-list handling), or terms starting with "%" (e.g.
    # metric names like "%-Anteil Klassen und Pakete in Zyklen").
    my $term_start = qr/(?:$PARAGRAPH_START|&\#x3[0-9];\.|%)/;

    # Only the top-level pass needs to look out for already-rendered nested
    # ::: divs (produced by the deeper pass) and pass them through as-is.
    my $children_clause = $allow_children ? q{
                (?:[ \t]*\n(?=:::))?
                (?:
                    :::.*\n
                    (?:(?!:::).*\n)*
                    :::\n
                    (?:[ \t]*\n(?=:::))?
                )*
    } : '';

    $text =~ s{
        \n\n\Q$pad\E($term_start.*)\n
        \n?
        (
            (?:
                \Q$pad\E:(?!:)[ \t]*.*\n
                (?:
                    \Q$pad\E[ \t]{2,}.*\n
                  | [ \t]*\n(?=\Q$pad\E[ \t]{2,}.*\n|\Q$pad\E:(?!:))
                )*
            )+
            $children_clause
        )
        \n*
    }{
        my $term = $1;
        my $defs_block = $2;

        # Split off any already-rendered nested definition lists (::: divs
        # produced by an earlier, deeper pass): they are passed through as-is.
        my @block_lines = split /\n/, $defs_block, -1;
        my $raw_start;
        if ($allow_children) {
            for my $i (0 .. $#block_lines) {
                if ($block_lines[$i] =~ /^:::/) {
                    $raw_start = $i;
                    last;
                }
            }
        }
        my $leading_lines = defined $raw_start ? join("\n", @block_lines[0 .. $raw_start - 1]) : $defs_block;
        my $raw_lines = defined $raw_start ? join("\n", @block_lines[$raw_start .. $#block_lines]) : '';
        $raw_lines =~ s/\n+$//;

        my @defs;
        my $current = '';

        for my $line (split /\n/, $leading_lines) {
            my $stripped = $line;
            $stripped =~ s/^\Q$pad\E// if length $pad;
            if ($stripped =~ /^:(?!:)[ \t]*(.*)$/) {
                push @defs, $current if length $current;
                $current = $1;
            } elsif ($stripped =~ /^(?:[ \t]{2,}|\t)(.*)$/) {
                push @defs, $current if length $current;
                $current = $1;
            } elsif ($stripped =~ /^[ \t]*$/) {
                # Blank line: end of the current paragraph within this definition
                push @defs, $current if length $current;
                $current = '';
            } else {
                $current .= "\n$stripped";
            }
        }
        push @defs, $current if length $current;

        my $out = "\n\n::: {custom-style=\"$styles{$def_style_key}\"}\n[$term]{custom-style=\"$styles{$term_style_key}\"}\n:::\n";
        $out .= join '', map { "::: {custom-style=\"$styles{$def_con_style_key}\"}\n$_\n:::\n" } @defs;
        $out .= "$raw_lines\n" if length $raw_lines;
        $out . "\n";
    }gmex;

    return $text;
}

# Has to be called before translateSubHeadings() to determine first paragraphs
sub translateBodyText {
    my $text = shift;

    # Dialogues
    $text =~ s/(\n(?!\*{4}).*\n\n+)\*{4}(.*?:)\*{4}(.*?)\n/$1::: {custom-style="$styles{'DLG_FIRST'}"}\n[$2]{custom-style="$styles{'DLG_SPKR'}"} $3\n:::\n/g;
    $text =~ s/\n\*{4}(.*?:)\*{4}(.*?)(\n\n+(?!\*{4}).*\n)/\n::: {custom-style="$styles{'DLG_LAST'}"}\n[$1]{custom-style="$styles{'DLG_SPKR'}"} $2\n:::$3/g;
    $text =~ s/^\*{4}(.*?:)\*{4}(.*)$/::: {custom-style="$styles{'DLG_MID'}"}\n[$1]{custom-style="$styles{'DLG_SPKR'}"} $2\n:::/gm;
    # Tips, Notes, Warnings
    # (block-wise: a callout may span several paragraphs, written as consecutive
    #  I>/T>/W> lines with bare I>/T>/W> lines as paragraph separators —
    #  emit the NOTE/TIP/WARNING title only once per block)
    $text =~ s{^([ITW])> .*(?:\n\1>(?: .*)?)*$}{translateCallout($&)}gme;
    # Paragraphs, first after heading
    $text =~ s/((?:^|\n)#.*(?:\n+>.*)?(?:\n+\!.*)?)\n\n+(?!$NATIVE_TABLE_CAPTION)($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'HEADFIRST'}"}\n$2\n:::\n\n/gm; # First paragraph after heading with optional epigraph and optional opening picture
    $text =~ s/((?:^|\n)#.*(?:\n+\!.*)?)\n\n+(?!$NATIVE_TABLE_CAPTION)($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'HEADFIRST'}"}\n$2\n:::\n\n/gm; # Doppelt für gerade Absatznummer
    # Paragraphs, first after list
    $text =~ s/(^ *- .*)\n\n+(?!$NATIVE_TABLE_CAPTION)($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'paragraph_first_after_list'}"}\n$2\n:::\n\n/gm; # First paragraph after bulleted list
    $text =~ s/(^ *- .*)\n\n+(?!$NATIVE_TABLE_CAPTION)($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'paragraph_first_after_list'}"}\n$2\n:::\n\n/gm; # Doppelt für gerade Absatznummer
    $text =~ s/(^ *\d+\. .*)\n\n+(?!$NATIVE_TABLE_CAPTION)($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'paragraph_first_after_list'}"}\n$2\n:::\n\n/gm; # First paragraph after numbered list
    $text =~ s/(^ *\d+\. .*)\n\n+(?!$NATIVE_TABLE_CAPTION)($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'paragraph_first_after_list'}"}\n$2\n:::\n\n/gm; # Doppelt für gerade Absatznummer
    # Paragraphs, first after figure
    # Paragraphs, first after quote
    # Paragraphs, first after table
    # Paragraphs, normal
    $text =~ s/\n\n(?!$NATIVE_TABLE_CAPTION)($PARAGRAPH_START.*)\n+/\n\n::: {custom-style="$styles{'CHAP_BM'}"}\n$1\n:::\n\n/gm;  # einmal für ungerade Absatznummer
    $text =~ s/\n\n(?!$NATIVE_TABLE_CAPTION)($PARAGRAPH_START.*)\n+/\n\n::: {custom-style="$styles{'CHAP_BM'}"}\n$1\n:::\n\n/gm;  # Doppelt für Gerade Absatznummer
    # Epigraphs
    $text =~ s/(^# .*\n+)> (.*)(—.*)$/$1::: {custom-style="$styles{'CF_EPG_FIRST'}"}\n$2\n:::\n::: {custom-style="$styles{'CF_EPG_ATTR_AU_NA'}"}\n$3\n:::\n/gm; # Opening epigraph
    $text =~ s/(^##+ .*\n+)> (.*)(—.*)$/$1::: {custom-style="$styles{'EPG'}"}\n$2\n:::\n::: {custom-style="$styles{'EPG_ATTR_AU_NA'}"}\n$3\n:::/gm;  # Epigraph with author
    $text =~ s/(^##+ .*\n+)> (.*)$/$1::: {custom-style="$styles{'EPG'}"}\n$2\n:::/gm;  # Epigraph
    # Block Quotations
    $text =~ s/^> (.*)$/::: {custom-style="$styles{'EXT_ONLY'}"}\n$1\n:::/gm;  # Extract

# TODO:
#       [^fn]:      Footnotes   -> custom-style="FN"
#        {blockquote}           =>   {custom-style="EXT_ONLY"}   ???

    return $text;
}

sub translateSubHeadings {
    my $text = shift;

    $text =~ s/^## (.*)$/::: {custom-style="$styles{'H1'}"}\n$1\n:::/gm;
    $text =~ s/^### (.*)$/::: {custom-style="$styles{'H2'}"}\n$1\n:::/gm;
    $text =~ s/^#### (.*)$/::: {custom-style="$styles{'H3'}"}\n$1\n:::/gm;
    
    return $text;
}

sub translateCallout {
    my $block = shift;
    my ($letter) = $block =~ /^([ITW])>/;
    my %title       = (I => $settings{'note_title'} // 'NOTE',
                        T => $settings{'tip_title'} // 'TIP',
                        W => $settings{'warning_title'} // 'WARNING');
    my %title_style = (I => $styles{'SF1_TTL'},  T => $styles{'SF2_TTL'},  W => $styles{'SF2_TTL'});
    my %para_style  = (I => $styles{'SF1_FIRST'},T => $styles{'SF2_FIRST'},W => $styles{'SF2_FIRST'});

    $block =~ s/^[ITW]> ?//gm;   # strip prefixes; bare separator lines become empty lines

    my $out = qq{::: {custom-style="$title_style{$letter}"}\n$title{$letter}\n:::};
    for my $paragraph (split /\n\s*\n/, $block) {
        $out .= qq{\n::: {custom-style="$para_style{$letter}"}\n$paragraph\n:::};
    }
    return $out;
}

sub translateLists {
    my ($text) = @_;

    # Following paragraph in lists
    # (3 or 4 spaces of indentation: extracts converted to asides lose one space of indentation,
    # because "> " is stripped, so continuation paragraphs in boxes arrive with only 3 spaces)
    $text =~ s/\n(- .*)\n\n? {3,4}(\S.*)\n\n? {3,4}(\S.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n::: {custom-style="$styles{'BL_CON'}"}\n$3\n:::\n/gm;
    $text =~ s/\n(- .*)\n\n? {3,4}(\S.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n/gm;
    $text =~ s/\n(\d+\. .*)\n\n? {3,4}(\S.*)\n\n? {3,4}(\S.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n::: {custom-style="$styles{'BL_CON'}"}\n$3\n:::\n/gm;
    $text =~ s/\n(\d+\. .*)\n\n? {3,4}(\S.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n/gm;
##    $text =~ s/\n(> - .*)\n\n?>     (.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n/gm;
    # TODO: BL_CON_LAST
    # TODO: BL_CDT

    # Bulleted, level 1
    $text =~ s/\n\n- (.*)\n/\n\n::: {custom-style="$styles{'BL_FIRST'}"}\n$1\n:::\n/gm;
    $text =~ s/\n- (.*)\n\n/\n::: {custom-style="$styles{'BL_LAST'}"}\n$1\n:::\n\n/gm;
    $text =~ s/^- (.*)$/::: {custom-style="$styles{'BL_MID'}"}\n$1\n:::/gm;            
    unless ($settings{'bullets_have_their_own_style'}) {
        # Bulleted, level 2
        $text =~ s/(\n(?!  -).*?\n+)  - (.*?)\n/$1::: {custom-style="$styles{'BL_BL_FIRST'}"}\n$2\n:::\n/gm;
        $text =~ s/\n  - (.*?)(\n+(?!  -))/\n::: {custom-style="$styles{'BL_BL_LAST'}"}\n$1\n:::$2/gm;
        $text =~ s/^  - (.*)$/::: {custom-style="$styles{'BL_BL_MID'}"}\n$1\n:::/gm;                               
        # Bulleted, level 3
        $text =~ s/(\n(?!    -).*?\n+)    - (.*?)\n/$1::: {custom-style="$styles{'BL_BL_BL_FIRST'}"}\n$2\n:::\n/gm;
        $text =~ s/\n    - (.*?)(\n+(?!    -))/\n::: {custom-style="$styles{'BL_BL_BL_LAST'}"}\n$1\n:::$2/gm;
        $text =~ s/^    - (.*)$/::: {custom-style="$styles{'BL_BL_BL_MID'}"}\n$1\n:::/gm;   
    } else {
        # Bulleted, level 2
        $text =~ s/(\n(?!  -).*?\n+)  - (.*?)\n/$1::: {custom-style="$styles{'BL_BL_FIRST'}"}\n\[$settings{'bullet_level_2'}\]{custom-style="$styles{'BL_BL_DING'}"}\t$2\n:::\n/gm;
        $text =~ s/\n  - (.*?)(\n+(?!  -))/\n::: {custom-style="$styles{'BL_BL_LAST'}"}\n\[$settings{'bullet_level_2'}\]{custom-style="$styles{'BL_BL_DING'}"}\t$1\n:::$2/gm;
        $text =~ s/^  - (.*)$/::: {custom-style="$styles{'BL_BL_MID'}"}\n\[$settings{'bullet_level_2'}\]{custom-style="$styles{'BL_BL_DING'}"}	$1\n:::/gm;                               
        # Bulleted, level 3
        $text =~ s/(\n(?!    -).*?\n+)    - (.*?)\n/$1::: {custom-style="$styles{'BL_BL_BL_FIRST'}"}\n\[$settings{'bullet_level_3'}\]{custom-style="$styles{'BL_BL_BL_DING'}"}\t$2\n:::\n/gm;
        $text =~ s/\n    - (.*?)(\n+(?!    -))/\n::: {custom-style="$styles{'BL_BL_BL_LAST'}"}\n\[$settings{'bullet_level_3'}\]{custom-style="$styles{'BL_BL_BL_DING'}"}\t$1\n:::$2/gm;
        $text =~ s/^    - (.*)$/::: {custom-style="$styles{'BL_BL_BL_MID'}"}\n\[$settings{'bullet_level_3'}\]{custom-style="$styles{'BL_BL_BL_DING'}"}	$1\n:::/gm;   
    }
    # Numbered: whether an item opens, continues or closes its list depends on
    # where it stands, not on the number written in the manuscript. Markdown lets
    # every item read "1.", and a list may run past nine items.
    $text = translateNumberedLists($text, '', 'NL_FIRST', 'NL_MID', 'NL_LAST');
    $text = translateNumberedLists($text, '    ', 'NL_NL_FIRST', 'NL_NL_MID', 'NL_NL_LAST');

    return $text;
}

sub translateNumberedLists {
    my ($text, $indent, $first, $mid, $last) = @_;

    my @lines = split /\n/, $text, -1;
    my $item = qr/^\Q$indent\E(\d+)\. (.*)$/;

    # A continuation paragraph has already been wrapped into a block of its own
    # above; it still belongs to the item it follows.
    # A template without a BL_CON style has no continuation block to look for.
    # Falling back to an empty style name would match the empty custom-style divs
    # that a template with missing keys emits, and read them as continuations.
    my $continuationStart = $styles{'BL_CON'}
        ? '::: {custom-style="' . $styles{'BL_CON'} . '"}'
        : undef;

    my $previous = sub {
        my $i = shift;
        $i-- while $i >= 0 && $lines[$i] eq '';
        return $i;
    };
    my $following = sub {
        my $i = shift;
        $i++ while $i <= $#lines && $lines[$i] eq '';
        return $i;
    };

    # The closest line above belongs to the same list: an item, or the end of a
    # continuation block.
    my $continuesAbove = sub {
        my $j = $previous->(shift() - 1);
        return 0 if $j < 0;
        return 1 if $lines[$j] =~ $item;
        return 0 unless $lines[$j] eq ':::';
        my $depth = 1;
        for (my $k = $j - 1; $k >= 0; $k--) {
            if ($lines[$k] eq ':::') { $depth++; }
            elsif ($lines[$k] =~ /^::: \{/) { return defined $continuationStart && $lines[$k] eq $continuationStart if --$depth == 0; }
        }
        return 0;
    };

    # The closest line below belongs to the same list: an item, or the start of a
    # continuation block.
    my $continuesBelow = sub {
        my $j = $following->(shift() + 1);
        return 0 if $j > $#lines;
        return $lines[$j] =~ $item || (defined $continuationStart && $lines[$j] eq $continuationStart);
    };

    my @result;
    for my $i (0 .. $#lines) {
        unless ($lines[$i] =~ $item) {
            push @result, $lines[$i];
            next;
        }
        my ($number, $content) = ($1, $2);
        my $style = ($number == 1 && !$continuesAbove->($i)) ? $first
                  : $continuesBelow->($i)                    ? $mid
                  :                                              $last;
        # Templates with a number style print the number as the manuscript wrote it.
        $content = "[$number.]{custom-style=\"$styles{'NL_NUM'}\"} $content" if $styles{'NL_NUM'};
        push @result, qq{::: {custom-style="$styles{$style}"}}, $content, ':::';
    }
    return join "\n", @result;
}

sub translateTables {
    my $text = shift;

    # Tables in extract like normal tables
    $text =~ s/^> ?(\|)/$1/gm;      
    $text =~ s/^> ?(Table: )/$1/gm;  # Table captions in extract like normal table captions
    $text =~ s/^> ?(Table|Tabelle|Tab\.[ | ][0-9IVX\.\-]+: )/$1/gm;  # Table captions in extract like normal table captions

    # Table captions
#    $text =~ s/^Table: (.*)$/: $1/gm;
    $text =~ s/^(Table|Tabelle|Tab\.)[ | ]([0-9IVX\.\-]+): (.*?) *\{(#.*)\}$/::: {$4 custom-style="$styles{'TBL_TTL'}"}\n[$1 $2]{custom-style="$styles{'TBL_NUM'}"} $3\n:::/gm;


    return $text;
}

sub translateFigures {
    my $text = shift;

    $text =~ s/^\!\[(Figure|Abbildung|Abb\.)[ | ]([0-9IVX\.\-]*)(.*)\]\((.*)\)(.*)$/::: {custom-style="$styles{'ARTLIST'}"}\n![]($4)$5\n:::\n::: {custom-style="$styles{'FIG_TTL'}"}\n[$1 $2]{custom-style="$styles{'FIG_NUM'}"} $3\n:::/gm;
    $text =~ s/^(\!\[\].*)$/::: {custom-style="$styles{'ARTLIST'}"}\n$1\n:::/gm; # Image without caption
    $text =~ s/^\!\[(.+)\]\((.*)\)$/::: {custom-style="$styles{'ARTLIST'}"}\n![]($2)\n:::\n::: {custom-style="$styles{'FIG_TTL'}"}\n$1\n:::/gm; 
#    $text =~ s/^\!\[(.+)\]\((.*)\)\{(.*)\}$/::: {custom-style="$styles{'ARTLIST'}"}\n![]($2){$3}\n:::\n::: {custom-style="$styles{'FIG_TTL'}"}\n$1\n:::/gm; 

    return $text;
}

sub translateSourceCode {
    my $text = shift;

    # Code in lists like normal code
    $text =~ s{(^    ```.*?^    ```)}{removeStartingFourSpaces($1)}msge;

    # Code in extract like normal code
    $text =~ s/^> ?(```)/$1/gm;      
    $text =~ s/^> ?(    ```)/$1/gm;      # Code in lists in extract like normal code
    $text =~ s{(^ ?```.*?^ *```)}{removeStartingArrow($1)}msge; # Code in extract like normal code
    $text =~ s{(^ ?    ```.*?^ *```)}{removeStartingArrow($1)}msge; # Code in lists in extract like normal code
    $text =~ s/^> ?(Listing: )/$1/gm;  # Listing captions in extract like normal listing captions

    # TODO: make the following configurable
    # Shorten four spaces to two spaces
    $text =~ s{(^```.*?^```)}{replaceFourSpacesWithTwoSpaces($1)}msge;

    # Escaping
    $text =~ s{(^```.*?^```)}{escapeSpecialCharacters($1)}msge;

    # Syntax highlighting
    $text =~ s{(^```gherkin.*?^```)}{replaceWithGherkinCodeStyles($1)}msge;
    $text =~ s{(```java.*?```)}{replaceWithJavaCodeStyles($1)}msge;
    $text =~ s{(^```fsharp.*?^```)}{replaceWithFSharpCodeStyles($1)}msge;
    $text =~ s{(^```userstory.*?^```)}{replaceWithUserStoryCodeStyles($1)}msge;

    # Equations
    $text =~ s/^```\$\n(.*?)\n```$/::: {custom-style="$styles{'EQ_ONLY'}"}\n$1\n:::/mg;

    #   body and line numbering
    $text =~ s{(^```.*?^```)}{replaceWithCodeBodyStyles($1)}msge;

    #   language-specific listing styles, one style per fenced block
    #   (only for templates that provide a `listing_language_styles` map)
    $text =~ s{(^```.*?^```)}{replaceWithListingLanguageStyle($1)}msge
        if ref $settings{'listing_language_styles'} eq 'HASH';
 
    # Code one-liner
    $text =~ s/^```.*?\n(.*?)\n```$/::: {custom-style="$styles{'CDT_ONLY'}"}\n$1\n:::/mg;

    # Code two-liner
    $text =~ s/^```.*?\n(\d+.*?)\n(.*?)\n```$/::: {custom-style="$styles{'DT_FIRST'}"}\n$1\n:::\n::: {custom-style="$styles{'DT_LAST'}"}\n$2\n:::/mg;
    $text =~ s/^```.*?\n(.*?)\n(.*?)\n```$/::: {custom-style="$styles{'CDT_FIRST'}"}\n$1\n:::\n::: {custom-style="$styles{'CDT_LAST'}"}\n$2\n:::/mg;

    # Code multi-liner
    #   start and end
    $text =~ s/^```.+\n(\[\d+\]\{custom\-style="$styles{'DT_NUM'}"\}.*)$/::: {custom-style="$styles{'DT_FIRST'}"}\n$1\n:::\n::: {custom-style="$styles{'DT_MID'}"}/gm;
    $text =~ s/^(.*)\n(\[\d+\]\{custom\-style="$styles{'DT_NUM'}"\}.*)\n```$/$1\n:::\n::: {custom-style="$styles{'DT_LAST'}"}\n$2\n:::\n/gm;  # End of Code-Block
    $text =~ s/^```.+\n(.*)$/::: {custom-style="$styles{'CDT_FIRST'}"}\n$1\n:::\n::: {custom-style="$styles{'CDT_MID'}"}/gm;
    $text =~ s/^(.*)\n(.*)\n```$/$1\n:::\n::: {custom-style="$styles{'CDT_LAST'}"}\n$2\n:::\n/gm;  # End of Code-Block
#    #   code in lists
#    $text =~ s/^    ```.+\n    (\[\d+\]\{custom\-style="$styles{'DT_NUM'}"\}.*)$/::: {custom-style="$styles{'BL_DT_FIRST'}"}\n$1\n:::\n::: {custom-style="$styles{'BL_DT_MID'}"}/gm;
#    $text =~ s/^(.*)\n    (\[\d+\]\{custom\-style="$styles{'DT_NUM'}"\}.*)\n    ```$/$1\n:::\n::: {custom-style="$styles{'BL_DT_LAST'}"}\n$2\n:::\n/gm;  # End of Code-Block
#    $text =~ s/^    ```.+\n    (.*)$/::: {custom-style="$styles{'BL_CDT_FIRST'}"}\n$1\n:::\n::: {custom-style="$styles{'BL_CDT_MID'}"}/gm;
#    $text =~ s/^(.*)\n(.*)\n    ```$/$1\n:::\n::: {custom-style="$styles{'BL_CDT_LAST'}"}\n$2\n:::\n/gm;  # End of Code-Block

    # code in text
    $text =~ s/`(..+?)`/\[$1\]{custom-style="$styles{'CIT'}"}/gm;

    # Listing captions
    $text =~ s/^Listing: (.*)$/```\n```\n\n: $1/gm;
#    $text =~ s/^: (.*)\n+```/```\n```\n\n: $1```/gm;

    return $text;
}

sub removeStartingArrow {
    my $text = shift;

    $text =~ s/^> //gm;   # remove starting >
    $text =~ s/^>//gm;   # remove starting >
 
    return $text;
}

sub removeStartingFourSpaces {
    my $text = shift;

    $text =~ s/^    //gm;   # remove starting 4 spaces
 
    return $text;
}

sub replaceFourSpacesWithTwoSpaces {
    my $text = shift;

    $text =~ s/    /  /gm;
 
    return $text;
}

sub escapeSpecialCharacters {
    my $text = shift;

    # Escape empty lines
    $text =~ s{^$}{&nbsp;}gm;

    # Escape Markdown special characters
    $text =~ s/\*/&ast;/gm;   # Escape asterisk
    $text =~ s/\</&lt;/gm;    # Escape opening angle bracket
    $text =~ s/\>/&gt;/gm;    # Escape closing angle bracket
    $text =~ s/\@/&#64;/gm;    # Escape at sign

    # Escape spaces
    $text =~ s/ /&nbsp;/gm;
    
    # Escape Pandoc's smart typography
    $text =~ s/\"/&quot;/gm;  # Escape double quotation marks
    $text =~ s/\'/&apos;/gm;  # Escape apostroph and single quotation marks
    $text =~ s/\.\.\./&#46;&#46;&#46;/gm;  # Escape ellipsis

    return $text;
}

sub replaceWithCodeBodyStyles {
    my $text = shift;

    #  code body
    $text =~ s/^    (.*)$/$1/gm;                          # Code block itself may start with 4 non-breaking (!!!) spaces
    $text =~ s/^(\d+)    (.*)$/\[$1\]{custom-style="$styles{'DT_NUM'}"} $2/gm;    # Numbered Code 
    $text =~ s/^(\d+)(.*)$/\[$1\]{custom-style="$styles{'DT_NUM'}"} $2/gm;    # Numbered Code 
    
    # Keep line breaks
    $text =~ s/^([^`].*)$/$1  /gm;

    return $text;
}

# Publishers whose template offers one listing style per programming language
# (e.g. dpunkt's V05 template with `Listing Java`, `Listing Python`, ...) get the
# whole fenced block in that one style. The fence's language is looked up in the
# template's `listing_language_styles` map; unmapped languages fall through to
# the generic CDT_* handling below.
sub replaceWithListingLanguageStyle {
    my $block = shift;

    my $language_styles = $settings{'listing_language_styles'};
    return $block unless ref $language_styles eq 'HASH';

    my @lines = split /\n/, $block, -1;
    my $fence = shift @lines;
    my ($language) = $fence =~ /^ *```[ \t]*([A-Za-z0-9_+#.-]+)/;
    return $block unless defined $language;

    my $style = $language_styles->{lc $language};
    return $block unless defined $style && $style ne '';

    return $block unless @lines && $lines[-1] =~ /^ *``` *$/;
    pop @lines;    # closing fence

    return qq(::: {custom-style="$style"}\n) . join("\n", @lines) . qq(\n:::);
}

sub replaceWithGherkinCodeStyles {
    my $text = shift;

    # keywords EN
    $text =~ s/(Scenario|Given|And|When|Then)(\s|:|&nbsp;)/\[$1\]{custom-style="$styles{'DT_BOLD'}"}$2/gm;
    # keywords DE
    $text =~ s/(Szenario|Gegeben&nbsp;sei|Und|Wenn|Dann)(\s|:|&nbsp;)/\[$1\]{custom-style="$styles{'DT_BOLD'}"}$2/gm;

    return $text;
}

sub replaceWithJavaCodeStyles {
    my $text = shift;

    # keywords
    $text =~ s/(import|package|class|enum|record)&nbsp;/\[$1\]{custom-style="$styles{'DT_BOLD'}"}&nbsp;/gm;
    $text =~ s/(final|static|public|protected|private)&nbsp;/\[$1\]{custom-style="$styles{'DT_BOLD'}"}&nbsp;/gm;
    $text =~ s/(new|assert|return)&nbsp;/\[$1\]{custom-style="$styles{'DT_BOLD'}"}&nbsp;/gm;
    $text =~ s/(var|void|boolean|char|byte|short|int|long|float|double)&nbsp;/\[$1\]{custom-style="$styles{'DT_BOLD'}"}&nbsp;/gm;
    
    # comments
    $text =~ s/(\/\/.*)$/\[$1\]{custom-style="$styles{'DT_ITAL'}"}/gm;
    $text =~ s/(\/&ast;.*?&ast;\/)/\[$1\]{custom-style="$styles{'DT_ITAL'}"}/gsm;

    return $text;
}

sub replaceWithFSharpCodeStyles {
    my $text = shift;

    # keywords
    $text =~ s/(type|of|let|fun|open)&nbsp;/\[$1\]{custom-style="$styles{'DT_BOLD'}"}&nbsp;/gm;

    # comments
    $text =~ s/(\(&ast;.*?&ast;\))/\[$1\]{custom-style="$styles{'DT_ITAL'}"}/gsm;

    return $text;
}

sub replaceWithUserStoryCodeStyles {
    my $text = shift;

    # Treat user stories as equations
    $text =~ s/```userstory/```\$/gm;

    # keywords EN
    $text =~ s/(As&nbsp;an?|I&nbsp;want|so&nbsp;that)/\[$1\]{custom-style="$styles{'BOLD'}"}/gm;
    # keywords DE
    $text =~ s/(Als&nbsp;eine?|möchte&nbsp;ich|damit|sodass)/\[$1\]{custom-style="$styles{'BOLD'}"}/gm;

    # placeholders
    $text =~ s/(&lt;.*?&gt;)/\[$1\]{custom-style="$styles{'ITAL'}"}/gm;

    return $text;
}

sub translateEmphasizement {
    my $text = shift;

    $text =~ s/\*\*(.*?)\*\*/\[$1\]{custom-style="$styles{'BOLD'}"}/gm;
    $text =~ s/\*(.*?)\*/\[$1\]{custom-style="$styles{'ITAL'}"}/gm;

    return $text;
}

sub translateDomainStorytellingEmphasizement {
    my $text = shift;

    # Eigene Hervorhebungen
    $text =~ s/{dst-term}/{}/gm;       # Domain Storytelling term      
    $text =~ s/{dst-def}/{custom-style="$styles{'BOLD'}"}/gm;       # definition of a term      
    $text =~ s/{dst-sf}/{custom-style="$styles{'SCAP'}"}/gm;        # scope factor      
    $text =~ s/{dst-sf-def}/{custom-style="$styles{'SCAP_BOLD'}"}/gm;    # definition of a scope factor      
    $text =~ s/(Back to the Leasing Example)/🚘 $1 🚘/gm; 
    $text =~ s/(Stefan|Henning)(\'s.*)(Story)/🌻 $1$2$3 🌻/gm;

    return $text;
}

sub translatePartText {
    my $text = shift;

    $text =~ s{(\n# Part.*?\n# )}{replaceWithStylesInPart($1)}msge;
    $text =~ s{(\n# Teil.*?\n# )}{replaceWithStylesInPart($1)}msge;
    $text =~ s{(\n# \N*? #\n.*?\n# )}{replaceWithStylesInPart($1)}msge;

    return $text;
}

sub replaceWithStylesInPart {
    my $text = shift;

    # Headings
    $text =~ s/"$styles{'H1'}"/"$styles{'PART_H1'}"/g;   
    $text =~ s/"$styles{'H2'}"/"$styles{'PART_H2'}"/g;

    # Paragraphs
    $text =~ s/"$styles{'HEADFIRST'}"/"$styles{'PART_FIRST'}"/g; #TODO: or PART_HEADFIRST??
    $text =~ s/"$styles{'CHAP_BM'}"/"$styles{'PART'}"/g;

    # Lists, bulleted
    $text =~ s/"$styles{'BL_FIRST'}"/"$styles{'PART_BL_FIRST'}"/g;
    $text =~ s/"$styles{'BL_MID'}"/"$styles{'PART_BL_MID'}"/g;
    $text =~ s/"$styles{'BL_LAST'}"/"$styles{'PART_BL_LAST'}"/g;

    # Code
    $text =~ s/"$styles{'CDT_ONLY'}"/"$styles{'PART_CDT_ONLY'}"/g;
    $text =~ s/"$styles{'CDT_FIRST'}"/"$styles{'PART_CDT_FIRST'}"/g;
    $text =~ s/"$styles{'CDT_MID'}"/"$styles{'PART_CDT_MID'}"/g;
    $text =~ s/"$styles{'CDT_LAST'}"/"$styles{'PART_CDT_LAST'}"/g;

    # Figures
    $text =~ s/"$styles{'FIG_TTL'}"/"$styles{'PART_FIG_TTL'}"/g;
    $text =~ s/"$styles{'FIG_NUM'}"/"$styles{'PART_FIG_NUM'}"/g;

    # Tables
# TODO:
#    $text =~ s/"$styles{'TBL'}"/"$styles{'PART_TBL'}"/g;
#    $text =~ s/"$styles{'TBL_COLHD'}"/"$styles{'PART_TBL_COLHD'}"/g;
    $text =~ s/"$styles{'TBL_TTL'}"/"$styles{'PART_TBL_TTL'}"/g;
    $text =~ s/"$styles{'TBL_NUM'}"/"$styles{'PART_TBL_NUM'}"/g;

    return $text;
}

sub translateAsides {
    my $text = shift;

    $text =~
        s{
            (
                \{aside\}
                .*?
                \{\/aside\}
            )
        }{
            replaceWithStylesInBox($1)
        }sxge;
    $text =~ s/^(\{\/?aside\})$/::: {custom-style="CHAP_BM_PD"}\n$1\n:::/gm;      

    return $text;
}

sub replaceWithStylesInBox {
    my $text = shift;

    # Headings
    $text =~ s/"$styles{'H1'}"/"$styles{'BX1_TTL'}"/g;
    $text =~ s/"$styles{'H2'}"/"$styles{'BX1_H1'}"/g;

    # Paragraphs
    $text =~ s/"$styles{'HEADFIRST'}"/"$styles{'BX1_FIRST'}"/g;
    $text =~ s/"$styles{'CHAP_BM'}"/"$styles{'BX1'}"/g;

    # Dialogue
    $text =~ s/"$styles{'DLG_FIRST'}"/"$styles{'BX1_DLG_FIRST'}"/g;
    $text =~ s/"$styles{'DLG_MID'}"/"$styles{'BX1_DLG_MID'}"/g;
    $text =~ s/"$styles{'DLG_LAST'}"/"$styles{'BX1_DLG_LAST'}"/g;

    # Equations
    $text =~ s/"$styles{'EQ_ONLY'}"/"$styles{'BX1_EQ_ONLY'}"/g;

    # Lists, bulleted
    unless ($settings{'bullets_have_their_own_style'}) {
        #       level 1
        $text =~ s/"$styles{'BL_FIRST'}"/"$styles{'BX1_BL_FIRST'}"/g;
        $text =~ s/"$styles{'BL_MID'}"/"$styles{'BX1_BL_MID'}"/g;
        $text =~ s/"$styles{'BL_LAST'}"/"$styles{'BX1_BL_LAST'}"/g;
        $text =~ s/"$styles{'BL_CON'}"/"$styles{'BX1_BL_CON'}"/g;
#        $text =~ s/"$styles{'BL_CON_LAST'}"/"$styles{'BX1_BL_CON_LAST'}/g;
    } else {
        #       level 1
        $text =~ s/::: \{custom-style="$styles{'BL_FIRST'}"\}\n(.*?)\n:::/::: {custom-style="$styles{'BX1_BL_FIRST'}"}\n[$settings{'bullet_in_box_level_1'}\]{custom-style="$styles{'BX1_BL_DING'}"}\t$1\n:::/gm;
        $text =~ s/::: \{custom-style="$styles{'BL_MID'}"\}\n(.*?)\n:::/::: {custom-style="$styles{'BX1_BL_MID'}"}\n[$settings{'bullet_in_box_level_1'}\]{custom-style="$styles{'BX1_BL_DING'}"}\t$1\n:::/gm;
        $text =~ s/::: \{custom-style="$styles{'BL_LAST'}"\}\n(.*?)\n:::/::: {custom-style="$styles{'BX1_BL_LAST'}"}\n[$settings{'bullet_in_box_level_1'}\]{custom-style="$styles{'BX1_BL_DING'}"}\t$1\n:::/gm;
        $text =~ s/::: \{custom-style="$styles{'BL_CON'}"\}\n(.*?)\n:::/::: {custom-style="$styles{'BX1_BL_CON'}"}\n$1\n:::/gm;
#        $text =~ s/::: \{custom-style="$styles{'BL_CON_LAST'}"\}\n(.*?)\n:::/::: {custom-style="$styles{'BX1_BL_CON_LAST'}"}\n$1\n:::/gm;
    }

    # Lists, numbered
    #       level 1
    $text =~ s/"$styles{'NL_FIRST'}"/"$styles{'BX1_NL_FIRST'}"/g;
    $text =~ s/"$styles{'NL_MID'}"/"$styles{'BX1_NL_MID'}"/g;
    $text =~ s/"$styles{'NL_LAST'}"/"$styles{'BX1_NL_LAST'}"/g;

    # Figures
    $text =~ s/"$styles{'FIG_TTL'}"/"$styles{'BX1_FIG_TTL'}"/g;
    $text =~ s/"$styles{'FIG_NUM'}"/"$styles{'BX1_FIG_NUM'}"/g;

    return $text;
}

sub translateForewordText {
    my $text = shift;

    $text =~ s{(^# (Series Editor Foreword|Geleitwort des Serienherausgebers).*?^# )}{replaceWithStylesInForeword($1)}msge;
    $text =~ s{(^# (Foreword|Geleitwort).*?^# )}{replaceWithStylesInForeword($1)}msge;
    $text =~ s{(^# Geleitwort.*?^# Vorwort)}{replaceWithStylesInForeword($1)}msge;

    return $text;
}

sub replaceWithStylesInForeword {
    my $text = shift;

    # Paragraphs
    $text =~ s/"HEADFIRST"/"BKFM_FRWRD_FIRST"/g;
    $text =~ s/"CHAP_BM"/"BKFM_FRWRD"/g;

    return $text;
}

sub translatePrefaceText {
    my $text = shift;

    $text =~ s{(^# (Preface|Vorwort).*?^# )}{replaceWithStylesInPreface($1)}msge;

    return $text;
}

sub replaceWithStylesInPreface {
    my $text = shift;

    # Headings
    $text =~ s/"H1"/"BKFM_PREF_H1"/g;
    $text =~ s/"H2"/"BKFM_PREF_H2"/g;

    # Paragraphs
    $text =~ s/"HEADFIRST"/"BKFM_PREF_FIRST"/g;
    $text =~ s/"CHAP_BM"/"BKFM_PREF"/g;
    $text =~ s/"CHAP_BM_CON"/"BKFM_PREF_CON"/g;

    # Lists, bulleted
    $text =~ s/"BL_FIRST"/"BKFM_PREF_BL_FIRST"/g;
    $text =~ s/"BL_MID"/"BKFM_PREF_BL_MID"/g;
    $text =~ s/"BL_LAST"/"BKFM_PREF_BL_LAST"/g;

    # Lists, numbered
    $text =~ s/"NL_FIRST"/"BKFM_PREF_NL_FIRST"/g;
    $text =~ s/"NL_MID"/"BKFM_PREF_NL_MID"/g;
    $text =~ s/"NL_LAST"/"BKFM_PREF_NL_LAST"/g;

    # Equations
    $text =~ s/"EQ"/"BKFM_PREF_EQ"/g;

    # Code
    $text =~ s/"CDT_ONLY"/"BKFM_PREF_CDT_ONLY"/g;
    $text =~ s/"CDT_FIRST"/"BKFM_PREF_CDT_FIRST"/g;
    $text =~ s/"CDT_MID"/"BKFM_PREF_CDT_MID"/g;
    $text =~ s/"CDT_LAST"/"BKFM_PREF_CDT_LAST"/g;

    # Tables
# TODO:
#    $text =~ s/"TBL"/"BKFM_PREF_TBL"/g;
#    $text =~ s/"TBL_COLHD"/"BKFM_PREF_TBL_COLHD"/g;
    $text =~ s/"TBL_TTL"/"BKFM_PREF_TBL_TTL"/g;
    $text =~ s/"TBL_NUM"/"BKFM_PREF_TBL_NUM"/g;

    return $text;
}

sub translateAcknowledgmentsText {
    my $text = shift;

    $text =~ s{(^# (Acknowledgments|Danksagung).*?^# )}{replaceWithStylesInAcknowledgments($1)}msge;

    return $text;
}

sub replaceWithStylesInAcknowledgments {
    my $text = shift;

    # Paragraphs
    $text =~ s/"HEADFIRST"/"BKFM_ACK_FIRST"/g;
    $text =~ s/"CHAP_BM"/"BKFM_ACK"/g;

# TODO:
#    # Author name
#    $text =~ s/"??"/"BKFM_ACK_AU_NA"/g;

    return $text;
}

sub translateAboutTheAuthorsText {
    my $text = shift;

    $text =~ s{(^# About the Authors?.*?(?:^# |\Z))}{replaceWithStylesInAboutTheAuthors($1)}msge;

    return $text;
}

sub replaceWithStylesInAboutTheAuthors {
    my $text = shift;

    # Paragraphs
    $text =~ s/"HEADFIRST"/"BKFM_ABA_FIRST"/g;
    $text =~ s/"CHAP_BM"/"BKFM_ABA"/g;

    return $text;
}

sub translateAppendixText {
    my $text = shift;

    $text =~ s{(^# (Appendix|Anhang).*?^# )}{replaceWithStylesInAppendix($1)}msge;

    return $text;
}

sub replaceWithStylesInAppendix {
    my $text = shift;

    # Paragraphs
    $text =~ s/"HEADFIRST"/"BKRM_APP_HEADFIRST"/g;
    $text =~ s/"CHAP_BM"/"BKRM_APP_INDENT"/g;

# TODO:
#    # Figures
#    $text =~ s/"??"/"BKRM_FIG_TTL"/g;

    return $text;
}

sub translateBibliographyText {
    my $text = shift;

    $text =~ s{(^# (Bibliography|Literatur).*?^# )}{replaceWithStylesInBibliography($1)}msge;

    return $text;
}

sub replaceWithStylesInBibliography {
    my $text = shift;

    # Headings
    $text =~ s/"H1"/"BKRM_BIB_H1"/g;

    # Paragraphs
    $text =~ s/"HEADFIRST"/"BKRM_BIB_HEADFIRST"/g;
    $text =~ s/"CHAP_BM"/"BKRM_BIB_CHAP_BM"/g;

    return $text;
}

sub translateLevelOneHeadings {
    my $text = shift;

    # Frontmatter
    $text =~ s/^# Praise for (.*)$/\n\n{{newpage}}\n\n::: {custom-style="BKFM_PP_TTL"}\nPraise for $1\n:::/gm;
    $text =~ s/^# Domain Stor(ie|y)s$/\n\n{{newpage}}\n\n::: {custom-style="BKFM_TOC_FIG_TTL"}\nDomain Stor$1s\n:::/gm;
    $text =~ s/^# (Figures|Abbildungen)$/\n\n{{newpage}}\n\n::: {custom-style="BKFM_TOC_FIG_TTL"}\n$1\n:::/gm;
    $text =~ s/^# ((Series Editor )?Foreword)$/\n\n{{newpage}}\n\n::: {custom-style="BKFM_FRWRD_TTL"}\n$1\n:::/gm;
    $text =~ s/^# (Geleitwort.*)$/\n\n{{newpage}}\n\n::: {custom-style="BKFM_FRWRD_TTL"}\n$1\n:::/gm;
    $text =~ s/^# (Preface|Vorwort)$/\n\n{{newpage}}\n\n::: {custom-style="BKFM_PREF_TTL"}\n$1\n:::/gm;
    $text =~ s/^# (Acknowledgments|Danksagung)$/\n\n{{newpage}}\n\n::: {custom-style="BKFM_ACK_TTL"}\n$1\n:::/gm;
    $text =~ s/^# (About the Authors?)$/\n\n{{newpage}}\n\n::: {custom-style="BKFM_ABASET_TTL"}\n$1\n:::/gm;

    # Headings Backmatter
    $text =~ s/^# (Appendix|Anhang) (.*): (.*)$/\n\n{{newpage}}\n\n::: {custom-style="BKRM_APP_LET"}\n$1 $2\n:::\n::: {custom-style="BKRM_APP_TTL"}\n$3\n:::/gm;
    $text =~ s/^# (Appendix|Anhang): (.*)$/\n\n{{newpage}}\n\n::: {custom-style="BKRM_APP_LET"}\n$1\n:::\n::: {custom-style="BKRM_APP_TTL"}\n$2\n:::/gm;
    $text =~ s/^# (Glossary?)$/\n\n{{newpage}}\n\n::: {custom-style="BKRM_GLOSSET_TTL"}\n$1\n:::/gm;
    $text =~ s/^# (Bibliography|Literatur)$/\n\n{{newpage}}\n\n::: {custom-style="$styles{'BKRM_BIB_TTL'}"}\n$1\n:::/gm;
    $text =~ s/^# Index$/\n\n{{newpage}}\n\n::: {custom-style="BKRM_IDX_TTL"}\nIndex\n:::/gm;

    # Headings Mainmatter
    $text =~ s/\n(\{.*\})\n(#.*?)\n/\n\n$2\n$1\n\n/gm; #Move beginning {} with link anchors to end of heading
    $text =~ s/^# (Part|Teil) (.*): (.*) #$/\n\n{{newpage}}\n\n::: {custom-style="$styles{'PART_NUM'}"}\n$1 $2\n:::\n::: {custom-style="$styles{'PART_TTL'}"}\n$3\n:::/gm;
    $text =~ s/^# (.*) #$/\n\n::: {custom-style="$styles{'PART_TTL'}"}\n$1\n:::/gm;
    $text =~ s/^# (Chapter|Kapitel) (.*): (.*)$/\n\n{{newpage}}\n\n::: {custom-style="$styles{'CHAP_NUM'}"}\n$1 $2\n:::\n::: {custom-style="$styles{'CHAP_TTL'}"}\n$3\n:::/gm;
    
    # Delete starting empty page
    $text =~ s/^\n*\{\{newpage\}\}\n*//;

    return $text;
}

sub removeMarkupForStandardStyles {
    my $text = shift;

    # Styles that Pandoc handles natively are unwrapped again, so that e.g. the
    # {#sec:...} labels stay on real headings. The names come from the template's
    # %styles, because they differ per template ('Standard' vs. 'Normal',
    # 'Überschrift 1' vs. 'heading 1', ...).
    $text =~ s{^::: \{custom-style="\Q$styles{'HEADFIRST'}\E"\}\n(.*?)\n:::}{$1}msg;
    $text =~ s{^::: \{custom-style="\Q$styles{'CHAP_TTL'}\E"\}\n(.*?)\n:::}{# $1}msg;
    $text =~ s{^::: \{custom-style="\Q$styles{'H1'}\E"\}\n(.*?)\n:::}{## $1}msg;
    $text =~ s{^::: \{custom-style="\Q$styles{'H2'}\E"\}\n(.*?)\n:::}{### $1}msg;
    $text =~ s{^::: \{custom-style="\Q$styles{'H3'}\E"\}\n(.*?)\n:::}{#### $1}msg;

    return $text;
}

1;
