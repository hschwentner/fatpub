#!/usr/bin/env perl
# replaceWithListingLanguageStyle() puts a whole fenced code block into one
# language-specific paragraph style, for publisher templates that offer one
# listing style per programming language (dpunkt's V05 template has
# `Listing Java`, `Listing Python`, ... — see bin/markua2dpunkt_V05).
#
# The language is taken from the fence's info string and looked up in the
# template's `listing_language_styles` map. Anything the map does not know
# is returned unchanged, so it falls through to the generic CDT_* handling
# in translateSourceCode() (lib/Markua2Styles.pm).
#
# Templates that define no such map (ptg_awph02, dpunkt_einspaltig,
# dpunkt_2019) must be completely unaffected — that is the last test here.

use strict;
use warnings;
use utf8;

use Test::More;
binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use lib 'lib';
require Markua2Styles;

sub listing { return Markua2Styles::replaceWithListingLanguageStyle(@_) }

# The function reads the module's package-global %settings, which
# Markua2Styles() normally fills from the template's %settings hash.
local %Markua2Styles::settings = (
    listing_language_styles => {
        'java'   => 'Listing Java',
        'python' => 'Listing Python',
    },
);

my $java_block = "```java\npublic class A {\n}\n```";

is( listing($java_block),
    qq(::: {custom-style="Listing Java"}\npublic class A {\n}\n:::),
    'a mapped language wraps the whole block in that one style' );

is( listing("```python\nx = 1\n```"),
    qq(::: {custom-style="Listing Python"}\nx = 1\n:::),
    'a second mapped language picks its own style' );

is( listing("```JAVA\npublic class A {\n}\n```"),
    qq(::: {custom-style="Listing Java"}\npublic class A {\n}\n:::),
    'the language match is case-insensitive' );

is( listing("```java {.numberLines}\npublic class A {\n}\n```"),
    qq(::: {custom-style="Listing Java"}\npublic class A {\n}\n:::),
    'further attributes on the fence line do not hide the language' );

# The body is passed through verbatim; replaceWithCodeBodyStyles() has
# already added the two trailing spaces that keep the line breaks.
is( listing("```java\nline one  \nline two  \nline three  \n```"),
    qq(::: {custom-style="Listing Java"}\nline one  \nline two  \nline three  \n:::),
    'keeps every body line, including the trailing hard-break spaces' );

is( listing("```ruby\nputs 1\n```"),
    "```ruby\nputs 1\n```",
    'an unmapped language is left for the generic CDT_* handling' );

is( listing("```\nplain\n```"),
    "```\nplain\n```",
    'a fence without a language is left untouched' );

is( listing("```\$\nE = mc^2\n```"),
    "```\$\nE = mc^2\n```",
    'an equation block is not mistaken for a language' );

is( listing("```java\npublic class A {\n"),
    "```java\npublic class A {\n",
    'a block without a closing fence is left untouched' );

# Backward compatibility: the templates that ship no language map must see
# their code blocks completely unchanged.
{
    local %Markua2Styles::settings = ( note_title => 'HINWEIS' );
    is( listing($java_block), $java_block,
        'without a listing_language_styles map the block is unchanged' );
}

done_testing();
