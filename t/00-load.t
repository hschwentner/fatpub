#!/usr/bin/env perl
# Smoke test: the module loads and exposes the interface the bin/ scripts rely on.

use strict;
use warnings;
use utf8;

use Test::More;
binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use lib 'lib';

require_ok('Markua2Styles');

like( $Markua2Styles::VERSION, qr/^\d+\.\d+$/, 'VERSION is set and looks like a version' );

is_deeply( \@Markua2Styles::EXPORT, ['Markua2Styles'],
    'exports exactly Markua2Styles(), the entry point bin/markua2* call' );

can_ok( 'Markua2Styles', qw(
    Markua2Styles
    cleanup
    cleanupGermanAbbreviations
    translateSpecialAsides
) );

done_testing();
