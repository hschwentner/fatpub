#!/usr/bin/env perl
# Index entries ({i: "term"}) must not reach the output of a template that does
# not ask for Word index fields.
#
# This is tested through the whole pipeline rather than through the one sub that
# happens to strip them. Which sub that is has already moved once — it was the
# last substitution in cleanup(), and #1 moves it into extractIndexEntries() so
# that entries stay out of the translation passes — and the property that
# matters holds either way: an entry is gone by the time the passes run, and
# nothing of it is left in the output.
#
# The last two tests pin the two ways that went wrong when entries were left in
# the text until the end of the pipeline.

use strict;
use warnings;
use utf8;

use Test::More;
binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use lib 'lib';
require Markua2Styles;

# Every style key the module mentions, mapped to its own name. Read from the
# source so that a newly referenced key cannot quietly make this test warn, and
# so the test is not tied to one publisher's table.
sub identity_styles {
    open my $fh, '<:encoding(UTF-8)', 'lib/Markua2Styles.pm'
        or die "cannot read the module: $!";
    my $source = do { local $/; <$fh> };
    return map { $_ => $_ } $source =~ /\$styles\{'([A-Za-z0-9_]+)'\}/g;
}

# Runs the full pipeline with no settings, so index_entries is unset and entries
# are dropped — what every template except dpunkt_V05 does. Any warning is a
# failure: a missing style key would mean this test is no longer exercising what
# it claims to.
sub convert {
    my $markua = shift;
    my %styles = identity_styles();
    my @warnings;
    my $out = do {
        local $SIG{__WARN__} = sub { push @warnings, $_[0] };
        Markua2Styles::Markua2Styles($markua, {}, \%styles);
    };
    fail("unexpected warning: $_") for @warnings;
    return $out;
}

my $one = convert("First.\n\nSome {i:index entry}text here.\n\nLast.\n");
unlike( $one, qr/\{i:/, 'no index entry survives the pipeline' );
like(   $one, qr/Some text here\./, 'the text around the entry is kept, joined up' );

my $many = convert("First.\n\na {i:one} b {i:two} c\n\nLast.\n");
like( $many, qr/a  b  c/, 'every entry on a line is removed, not just the first' );

# An entry whose term contains emphasis markers. While entries were left in the
# text until the last pass, translateEmphasizement rewrote the term into
# [term]{custom-style="..."}, whose brace then ended the {i:...} match early and
# left the tail of the entry standing in the output.
my $emphasised = convert("First.\n\nA term{i: \"the *star* term\"} inside it.\n\nLast.\n");
unlike( $emphasised, qr/term"\}/, 'an entry whose term contains * leaves no tail behind' );
like(   $emphasised, qr/A term inside it\./, 'and the sentence around it is intact' );

# A paragraph that opens with an entry. While entries survived the passes, the
# leading "{" meant $PARAGRAPH_START did not match and the paragraph lost its
# body style altogether.
my $leading = convert("First.\n\nSecond.\n\n{i: \"term\"}According to the authors, this holds.\n\nLast.\n");
like( $leading, qr/\Q::: {custom-style="CHAP_BM"}\E\nAccording to the authors/,
    'a paragraph opening with an entry still gets its body style' );


# --- the Markua index syntax -------------------------------------------
#
# https://help.leanpub.com/en/articles/6961502-how-to-create-an-index-in-a-leanpub-book
# and Leanpub's own sample book at leanpub/sample-book-with-index-entries.
# Entries are dropped here, so these check that every documented shape is
# recognised as one entry and leaves nothing of itself behind. What the Word
# field looks like is #1's business, and is tested there once it lands.

for my $case (
    [ 'Call me Ishmael{i: Ishmael}.',                 'Call me Ishmael.',      'a bare, unquoted term' ],
    [ 'A voyage{i: "voyage"}.',                       'A voyage.',             'a quoted term' ],
    [ 'The cataract{i: "Niagara!cataract"}.',         'The cataract.',         'levels separated by !' ],
    [ 'The sand{i: "Niagara!*sand*"}.',               'The sand.',             'inline markup in a term' ],
    [ 'Strange!{i: "Strange\\!"}.',                     'Strange!.',             'an escaped literal !' ],
    [ 'A Sabbath{i: "Sabbath, the"}.',                'A Sabbath.',            'a comma is part of the term' ],
) {
    my ($markua, $expected, $what) = @$case;
    my $out = convert("First.\n\n$markua\n\nLast.\n");
    unlike( $out, qr/\{i:/, "$what: nothing of the entry survives" );
    like(   $out, qr/\Q$expected\E/, "$what: the sentence is left intact" );
}

# A see or seealso reference nests another {i:...} inside the entry, and the
# pattern that drops entries is non-greedy, so it stops at the inner brace and
# leaves the tail of the entry in the text. #1 replaces that pattern with one
# that knows about the nesting; until it lands, these stay TODO.

TODO: {
    local $TODO = 'the drop pattern stops at the inner brace of a |see reference, '
                . 'leaving the rest of the entry in the text';

    for my $case (
        [ q{Silver{i: "Tennessee|see{i:'silver'}"}.},   'Silver.', 'a see reference, which nests {i:...}' ],
        [ q{A coat{i: "Tennessee|seealso{i:'coat'}"}.}, 'A coat.', 'a seealso reference' ],
    ) {
        my ($markua, $expected, $what) = @$case;
        like( convert("First.\n\n$markua\n\nLast.\n"), qr/\Q$expected\E/,
            "$what: the sentence is left intact" );
    }
}

done_testing();
