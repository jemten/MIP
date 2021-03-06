#!/usr/bin/env perl

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
use File::Spec::Functions qw{ catdir };
use FindBin qw{ $Bin };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
use Test::More;
use utf8;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use Modern::Perl qw{ 2014 };
use Readonly;

## MIPs lib/
use lib catdir( dirname($Bin), q{lib} );
use MIP::Test::Commands qw{ test_function };
use MIP::Test::Fixtures qw{ test_standard_cli };

my $VERBOSE = 1;
our $VERSION = 1.01;

$VERBOSE = test_standard_cli(
    {
        verbose => $VERBOSE,
        version => $VERSION,
    }
);

## Constants
Readonly my $COMMA => q{,};
Readonly my $SPACE => q{ };

BEGIN {

    use MIP::Test::Fixtures qw{ test_import };

### Check all internal dependency modules and imports
## Modules with import
    my %perl_module = (
        q{MIP::Program::Alignment::Samtools} => [qw{ samtools_view }],
        q{MIP::Test::Fixtures}               => [qw{ test_standard_cli }],
    );

    test_import( { perl_module_href => \%perl_module, } );
}

use MIP::Program::Alignment::Samtools qw{ samtools_view };
use MIP::Test::Commands qw{ test_function };

diag(   q{Test samtools_view from samtools.pl v}
      . $MIP::Program::Alignment::Samtools::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Base arguments
my @function_base_commands = qw{ samtools view };

my %base_argument = (
    FILEHANDLE => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
);

## Can be duplicated with %base and/or %specific to enable testing of each individual argument
my %required_argument = (
    FILEHANDLE => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
    infile_path => {
        input           => q{infile.test},
        expected_output => q{infile.test},
    },
);

## Specific arguments
my %specific_argument = (
    auto_detect_input_format => {
        input           => q{1},
        expected_output => q{-S},
    },
    exclude_reads_with_these_flags => {
        input           => q{1},
        expected_output => q{-F 1},
    },
    fraction => {
        input           => q{2.5},
        expected_output => q{-s 2.5},
    },
    outfile_path => {
        input           => q{outfilepath},
        expected_output => q{-o outfilepath},
    },
    output_format => {
        input           => q{sam},
        expected_output => q{--output-fmt SAM},
    },
    regions_ref => {
        inputs_ref      => [qw{ 1:1000000-2000000 2:1000-5000 }],
        expected_output => q{1:1000000-2000000 2:1000-5000},
    },
    referencefile_path => {
        input           => q{GRCh37_homo_sapiens.fasta},
        expected_output => q{--reference GRCh37_homo_sapiens.fasta},
    },
    stderrfile_path => {
        input           => q{stderrfile.test},
        expected_output => q{2> stderrfile.test},
    },
    stderrfile_path_append => {
        input           => q{stderrfile_path_append},
        expected_output => q{2>> stderrfile_path_append},
    },
    thread_number => {
        input           => q{6},
        expected_output => q{--threads 6},
    },
    uncompressed_bam_output => {
        input           => q{1},
        expected_output => q{-u},
    },
    with_header => {
        input           => q{1},
        expected_output => q{-h},
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&samtools_view;

## Test both base and function specific arguments
my @arguments = ( \%base_argument, \%specific_argument );

foreach my $argument_href (@arguments) {

    my @commands = test_function(
        {
            argument_href              => $argument_href,
            do_test_base_command       => 1,
            function_base_commands_ref => \@function_base_commands,
            module_function_cref       => $module_function_cref,
            required_argument_href     => \%required_argument,
        }
    );
}

done_testing();
