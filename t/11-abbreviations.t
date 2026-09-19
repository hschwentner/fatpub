#!/usr/bin/env perl
# cleanupGermanAbbreviations() inserts a narrow no-break space into German
# abbreviations, so Word does not break "z. B." across a line.
#
# The narrow no-break space is emitted as the ASCII entity &#x202f; for
# Pandoc, and the separator it replaces is either a plain space (U+0020) or
# a non-breaking space (U+00A0), or absent (lib/Markua2Styles.pm:100-107).
#
# NOTE: this file needs `use utf8`. Without it a literal "ä" in the source
# is the two bytes \xC3\xA4 rather than character U+00E4, the module's
# patterns (compiled under `use utf8`) do not match it, and these tests
# quietly stop testing anything.

use strict;
use warnings;
use utf8;

use Test::More;
binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use lib 'lib';
require Markua2Styles;

sub abbrev { return Markua2Styles::cleanupGermanAbbreviations(@_) }

my $NNBSP = '&#x202f;';   # what the module emits
my $NBSP  = "\x{a0}";     # written as an escape on purpose: a literal U+00A0
                          # is invisible and indistinguishable from a space.

# Every abbreviation the module knows about, as (first, second) halves.
my @abbreviations = (
    [ 'd', 'h' ],   # das heißt
    [ 'o', 'ä' ],   # oder ähnliche
    [ 'o', 'Ä' ],
    [ 's', 'u' ],   # siehe unten
    [ 'u', 'a' ],   # unter anderem
    [ 'u', 'ä' ],   # und ähnliche
    [ 'u', 'Ä' ],
    [ 'z', 'B' ],   # zum Beispiel
);

for my $pair (@abbreviations) {
    my ($a, $b) = @$pair;
    my $expected = "$a.$NNBSP$b.";

    is( abbrev("$a. $b."),      $expected, "$a. $b. — plain space" );
    is( abbrev("$a.$NBSP$b."),  $expected, "$a. $b. — non-breaking space" );
    is( abbrev("$a.$b."),       $expected, "$a.$b. — no space at all" );
}

# Running the pipeline twice must not double-convert: after the first pass
# the separator is the entity &#x202f;, which the [space, nbsp]? class no
# longer matches.
is( abbrev(abbrev('Wir nutzen z. B. Äpfel, d. h. Obst.')),
    abbrev('Wir nutzen z. B. Äpfel, d. h. Obst.'),
    'is idempotent' );

is( abbrev('Ein Satz über Äpfel und Birnen ohne Abkürzung.'),
    'Ein Satz über Äpfel und Birnen ohne Abkürzung.',
    'leaves text without abbreviations untouched' );

is( abbrev('Am Anfang z. B. und am Ende u. a.'),
    "Am Anfang z.${NNBSP}B. und am Ende u.${NNBSP}a.",
    'converts several abbreviations in one string' );

done_testing();
