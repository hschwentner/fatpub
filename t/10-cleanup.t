#!/usr/bin/env perl
# cleanup() strips Leanpub and HTML markup that must not reach Pandoc.
#
# It is a pure string -> string function with no dependency on %styles or
# %settings, so each of its substitutions can be tested on its own.
# One test per substitution, in source order (lib/Markua2Styles.pm:83-92).

use strict;
use warnings;
use utf8;

use Test::More;
binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use lib 'lib';
require Markua2Styles;

sub cleanup { return Markua2Styles::cleanup(@_) }

# Commented out for Leanpub, commented back in for DOCX. Runs before the
# %%-deletion below, so a %%::: fence survives as a real ::: fence.
is( cleanup(qq{%%::: {custom-style="CHAP_BM"}\n}),
    qq{::: {custom-style="CHAP_BM"}\n},
    'uncomments %%::: fences so Pandoc sees the custom-style div' );

is( cleanup("before\n%%a Leanpub comment\nafter\n"),
    "before\nafter\n",
    'deletes Leanpub comment lines, newline included' );

is( cleanup("before<!-- hidden -->after"),
    "beforeafter",
    'deletes inline HTML comments' );

is( cleanup("before<!-- spanning\ntwo lines -->after"),
    "beforeafter",
    'deletes HTML comments spanning several lines' );

# Markua's escaped line break becomes the two trailing spaces that Markdown
# needs for a hard break.
is( cleanup("first\\\nsecond"),
    "first  \nsecond",
    'turns a trailing backslash into two spaces' );

is( cleanup("first \\\nsecond"),
    "first  \nsecond",
    'absorbs the space before a trailing backslash rather than adding a third' );

is( cleanup("before\n   \nafter"),
    "before\n\nafter",
    'empties lines containing only whitespace' );

is( cleanup("before\n\n\n\nafter"),
    "before\n\nafter",
    'collapses runs of blank lines to at most one' );

is( cleanup("before\n{sample}\nafter\n"),
    "before\n\nafter\n",
    'strips the {sample} directive' );

is( cleanup("before\n{width: 70%}\nafter\n"),
    "before\n\nafter\n",
    'strips the {width} directive' );

is( cleanup("before\n{id: some-anchor}\nafter\n"),
    "before\n\nafter\n",
    'strips the {id} directive' );

is( cleanup("Some {i:index entry}text"),
    "Some text",
    'removes index entries' );

is( cleanup("a {i:first} b {i:second} c"),
    "a  b  c",
    'removes every index entry on a line, not just the first' );

# --- known defect -------------------------------------------------------
#
# The three directive substitutions (lines 89-91) use $ under /m, which
# matches *before* the newline, so they blank the line but leave its
# newline in place. They run *after* the blank-line collapse on line 88,
# so the blank lines they create are never collapsed and cleanup() ends up
# violating its own "Not more than 2 newlines" invariant.
#
# This is live: {width: ...} sits directly above a figure in 10 places
# across 3 chapters of domain-storytelling-book, so each one currently
# separates the directive's blank line from the figure it belongs to.
#
# Recorded as TODO rather than fixed, to keep the fix in its own commit.

TODO: {
    local $TODO = 'cleanup() collapses blank lines (line 88) before deleting '
                . '{sample}/{width}/{id} (lines 89-91), so those directives '
                . 'leave a stray blank line behind';

    unlike( cleanup("Text.\n\n{width: 70%}\n![Figure 1 A caption](img.png)\n"),
        qr/\n\n\n/,
        'no run of three or more newlines survives cleanup' );
}

done_testing();
