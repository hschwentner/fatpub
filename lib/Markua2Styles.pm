# Copyright (C) 2020-2023  Henning Schwentner
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

use v5.38;
use warnings;
use autodie;

use utf8;                # UTF8 in sourcecode
use open qw/:std :utf8/; # UTF8 in input and output

use Exporter 'import';
our $VERSION = '1.20';
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

    $text = cleanupGermanAbbreviations($text);

    $text = translateSpecialAsides($text);

    $text = translateFrontmatter($text);
    $text = translateBackmatter($text);

    $text = translateTables($text);
    $text = translateSourceCode($text);
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

    return $text;
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
    $text =~ s/\{i:.*?\}//gm;          # Ignore index entries

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

    $text =~ s{(\n\n> 🌹+.*?> 🌹+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> 🎬+.*?> 🎬+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> 💰+.*?> 💰+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    $text =~ s{(\n\n> 🚗+.*?> 🚗+\n\n)}{replaceSpecialExtractsWithAsides($1)}msge;
    
    return $text;
}

sub replaceSpecialExtractsWithAsides {
    my $text = shift;

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

our $PARAGRAPH_START = '[\[\*]*[A-ZÄÖÜa-z“„»@]';

# Has to be called before translateSubHeadings() to determine first paragraphs
sub translateBodyText {
    my $text = shift;

    # Dialogues
    $text =~ s/(\n(?!\*{4}).*\n\n+)\*{4}(.*?:)\*{4}(.*?)\n/$1::: {custom-style="$styles{'DLG_FIRST'}"}\n[$2]{custom-style="$styles{'DLG_SPKR'}"} $3\n:::\n/g;
    $text =~ s/\n\*{4}(.*?:)\*{4}(.*?)(\n\n+(?!\*{4}).*\n)/\n::: {custom-style="$styles{'DLG_LAST'}"}\n[$1]{custom-style="$styles{'DLG_SPKR'}"} $2\n:::$3/g;
    $text =~ s/^\*{4}(.*?:)\*{4}(.*)$/::: {custom-style="$styles{'DLG_MID'}"}\n[$1]{custom-style="$styles{'DLG_SPKR'}"} $2\n:::/gm;
    # Tips, Notes
    $text =~ s/^I> (.*)$/::: {custom-style="$styles{'SF1_TTL'}"}\nNote\n:::\n::: {custom-style="$styles{'SF1_FIRST'}"}\n$1\n:::/gm;
    $text =~ s/^T> (.*)$/::: {custom-style="$styles{'SF2_TTL'}"}\nTip\n:::\n::: {custom-style="$styles{'SF2_FIRST'}"}\n$1\n:::/gm;
    # Paragraphs, first after heading
    $text =~ s/((?:^|\n)#.*(?:\n+>.*)?(?:\n+\!.*)?)\n\n+($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'HEADFIRST'}"}\n$2\n:::\n\n/gm; # First paragraph after heading with optional epigraph and optional opening picture
    $text =~ s/((?:^|\n)#.*(?:\n+\!.*)?)\n\n+($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'HEADFIRST'}"}\n$2\n:::\n\n/gm; # Doppelt für gerade Absatznummer
    # Paragraphs, first after list
    $text =~ s/(^ *- .*)\n\n+($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'paragraph_first_after_list'}"}\n$2\n:::\n\n/gm; # First paragraph after bulleted list
    $text =~ s/(^ *- .*)\n\n+($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'paragraph_first_after_list'}"}\n$2\n:::\n\n/gm; # Doppelt für gerade Absatznummer
    $text =~ s/(^ *\d+\. .*)\n\n+($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'paragraph_first_after_list'}"}\n$2\n:::\n\n/gm; # First paragraph after numbered list
    $text =~ s/(^ *\d+\. .*)\n\n+($PARAGRAPH_START.*)\n+/$1\n\n::: {custom-style="$styles{'paragraph_first_after_list'}"}\n$2\n:::\n\n/gm; # Doppelt für gerade Absatznummer
    # Paragraphs, first after figure
    # Paragraphs, first after quote
    # Paragraphs, first after table
    # Paragraphs, normal
    $text =~ s/\n\n($PARAGRAPH_START.*)\n+/\n\n::: {custom-style="$styles{'CHAP_BM'}"}\n$1\n:::\n\n/gm;  # einmal für ungerade Absatznummer
    $text =~ s/\n\n($PARAGRAPH_START.*)\n+/\n\n::: {custom-style="$styles{'CHAP_BM'}"}\n$1\n:::\n\n/gm;  # Doppelt für Gerade Absatznummer
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

sub translateLists {
    my ($text) = @_;

    # Following paragraph in lists
    $text =~ s/\n(- .*)\n\n?    (.*)\n\n?    (.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n::: {custom-style="$styles{'BL_CON'}"}\n$3\n:::\n/gm;
    $text =~ s/\n(- .*)\n\n?    (.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n/gm;
    $text =~ s/\n(\d+\. .*)\n\n?    (.*)\n\n?    (.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n::: {custom-style="$styles{'BL_CON'}"}\n$3\n:::\n/gm;
    $text =~ s/\n(\d+\. .*)\n\n?    (.*)/\n$1\n::: {custom-style="$styles{'BL_CON'}"}\n$2\n:::\n/gm;
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
    unless ($styles{'NL_NUM'}) {
        # Numbered                            
        $text =~ s/(^1\.) (.*)$/::: {custom-style="$styles{'NL_FIRST'}"}\n$2\n:::/gm;
        $text =~ s/\n(\d+\.) (.*)(\n+[^\d\n])/\n::: {custom-style="$styles{'NL_LAST'}"}\n$2\n:::$3/gm;      
        $text =~ s/(^[2-9]\.) (.*)$/::: {custom-style="$styles{'NL_MID'}"}\n$2\n:::/gm;      
        # Numbered, level 2
        $text =~ s/^    (1\.) (.*)$/::: {custom-style="$styles{'NL_NL_FIRST'}"}\n$2\n:::/gm;
        $text =~ s/\n    (\d+\.) (.*)(\n+[^\d\n])/\n::: {custom-style="$styles{'NL_NL_LAST'}"}\n$2\n:::$3/gm;      
        $text =~ s/^    ([2-9]\.) (.*)$/::: {custom-style="$styles{'NL_NL_MID'}"}\n$2\n:::/gm;      
    } else  {
        # Numbered                            
        $text =~ s/(^1\.) (.*)$/::: {custom-style="$styles{'NL_FIRST'}"}\n\[$1\]{custom-style="$styles{'NL_NUM'}"} $2\n:::/gm;
        $text =~ s/\n(\d+\.) (.*)(\n+[^\d\n])/\n::: {custom-style="$styles{'NL_LAST'}"}\n\[$1\]{custom-style="$styles{'NL_NUM'}"} $2\n:::$3/gm;      
        $text =~ s/(^[2-9]\.) (.*)$/::: {custom-style="$styles{'NL_MID'}"}\n\[$1\]{custom-style="$styles{'NL_NUM'}"} $2\n:::/gm;      
        # Numbered, level 2
        $text =~ s/^    (1\.) (.*)$/::: {custom-style="$styles{'NL_NL_FIRST'}"}\n\[$1\]{custom-style="$styles{'NL_NUM'}"} $2\n:::/gm;
        $text =~ s/\n    (\d+\.) (.*)(\n+[^\d\n])/\n::: {custom-style="$styles{'NL_NL_LAST'}"}\n\[$1\]{custom-style="$styles{'NL_NUM'}"} $2\n:::$3/gm;      
        $text =~ s/^    ([2-9]\.) (.*)$/::: {custom-style="$styles{'NL_NL_MID'}"}\n\[$1\]{custom-style="$styles{'NL_NUM'}"} $2\n:::/gm;      
    }

    return $text;
}

sub translateTables {
    my $text = shift;

    # Tables in extract like normal tables
    $text =~ s/^> ?(\|)/$1/gm;      
    $text =~ s/^> ?(Table: )/$1/gm;  # Table captions in extract like normal table captions
    $text =~ s/^> ?(Table|Tabelle|Tab\.[ | ][0-9IVX\.\-]+: )/$1/gm;  # Table captions in extract like normal table captions

    # Table captions
#    $text =~ s/^Table: (.*)$/: $1/gm;
    $text =~ s/^(Table|Tabelle|Tab\.)[ | ]([0-9IVX\.\-]+): (.*?) *({#.*})$/::: {custom-style="$styles{'TBL_TTL'}"}\n[$1 $2]{custom-style="$styles{'TBL_NUM'}"} $3$4\n:::/gm;

    # Hack for table links. May interfere with pandoc-crossref.
    $text =~ s/\[\@tbl:([0-9IVX\.\-]+?)-(.*?)\]/[Table $1](#tbl:$1$2)/gm;

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

# TODO: Add English variants

    $text =~ s{^::: \{custom-style="Standard"\}\n(.*?)\n:::}{$1}msg;
    $text =~ s{^::: \{custom-style="Überschrift 1"\}\n(.*?)\n:::}{# $1}msg;
    $text =~ s{^::: \{custom-style="Überschrift 2"\}\n(.*?)\n:::}{## $1}msg;
    $text =~ s{^::: \{custom-style="Überschrift 3"\}\n(.*?)\n:::}{### $1}msg;
    $text =~ s{^::: \{custom-style="Überschrift 4"\}\n(.*?)\n:::}{#### $1}msg;

    return $text;
}

1;
