#!/usr/bin/env perl

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname  };
use File::Spec::Functions qw{ catdir catfile };
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
use MIP::Test::Fixtures qw{ test_standard_cli };

my $VERBOSE = 1;
our $VERSION = 1.00;

$VERBOSE = test_standard_cli(
    {
        verbose => $VERBOSE,
        version => $VERSION,
    }
);

## Constants
Readonly my $COMMA           => q{,};
Readonly my $EQUAL           => q{=};
Readonly my $MIN_MAP_QUALITY => q{30};
Readonly my $SPACE           => q{ };

BEGIN {

    use MIP::Test::Fixtures qw{ test_import };

### Check all internal dependency modules and imports
## Modules with import
    my %perl_module = (
        q{MIP::Program::Qc::Rseqc} => [qw{ rseqc_junction_annotation }],
        q{MIP::Test::Fixtures}     => [qw{ test_standard_cli }],
    );

    test_import( { perl_module_href => \%perl_module, } );
}

use MIP::Program::Qc::Rseqc qw{ rseqc_junction_annotation };
use MIP::Test::Commands qw{ test_function };

diag(   q{Test rseqc_junction_annotation from Rseqc.pm v}
      . $MIP::Program::Qc::Rseqc::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Base arguments
my @function_base_commands = qw{ junction_annotation.py };

my %base_argument = (
    FILEHANDLE => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
    stderrfile_path => {
        input           => q{stderrfile.test},
        expected_output => q{2> stderrfile.test},
    },
    stderrfile_path_append => {
        input           => q{stderrfile.test},
        expected_output => q{2>> stderrfile.test},
    },
    stdoutfile_path => {
        input           => q{stdoutfile.test},
        expected_output => q{1> stdoutfile.test},
    },
);

## Can be duplicated with %base_argument and/or %specific_argument
## to enable testing of each individual argument
my %required_argument = (
    bed_file_path => {
        input           => catfile(qw{ a test transcripts.bed }),
        expected_output => q{--refgene}
          . $EQUAL
          . catfile(qw{ a test transcripts.bed }),
    },
    infile_path => {
        input           => catfile(qw{ a test infile.bam }),
        expected_output => q{--input-file}
          . $EQUAL
          . catfile(qw{ a test infile.bam }),
    },
    outfiles_path_prefix => {
        input           => catfile(qw{test outfiles_prefix }),
        expected_output => q{--out-prefix}
          . $EQUAL
          . catfile(qw{ test outfiles_prefix }),
    },
);

my %specific_argument = (
    bed_file_path => {
        input           => catfile(qw{ a test transcripts.bed }),
        expected_output => q{--refgene}
          . $EQUAL
          . catfile(qw{ a test transcripts.bed }),
    },
    infile_path => {
        input           => catfile(qw{ a test infile.bam }),
        expected_output => q{--input-file}
          . $EQUAL
          . catfile(qw{ a test infile.bam }),
    },
    min_map_quality => {
        input           => $MIN_MAP_QUALITY,
        expected_output => q{--mapq} . $EQUAL . $MIN_MAP_QUALITY,
    },
    outfiles_path_prefix => {
        input           => catfile(qw{test outfiles_prefix }),
        expected_output => q{--out-prefix}
          . $EQUAL
          . catfile(qw{ test outfiles_prefix }),
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&rseqc_junction_annotation;

## Test both base and function specific arguments
my @arguments = ( \%base_argument, \%specific_argument );

ARGUMENT_HASH_REF:
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
