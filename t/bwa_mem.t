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
Readonly my $COMMA        => q{,};
Readonly my $DOUBLE_QUOTE => q{"};
Readonly my $SPACE        => q{ };
Readonly my $TAB          => q{\t};

BEGIN {

    use MIP::Test::Fixtures qw{ test_import };

### Check all internal dependency modules and imports
## Modules with import
    my %perl_module = (
        q{MIP::Program::Alignment::Bwa} => [qw{ bwa_mem }],
        q{MIP::Test::Fixtures}          => [qw{ test_standard_cli }],
    );

    test_import( { perl_module_href => \%perl_module, } );
}

use MIP::Program::Alignment::Bwa qw{ bwa_mem };
use MIP::Test::Commands qw{ test_function };

diag(   q{Test bwa_mem from Bwa.pm v}
      . $MIP::Program::Alignment::Bwa::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Base arguments
my @function_base_commands = qw{ bwa mem };

## Read group header line
my @read_group_headers = (
    $DOUBLE_QUOTE . q{@RG},
    q{ID:} . q{1_140128_H8AHNADXX_1-1-2A_GATCAG_1} . $TAB,
    q{SM:} . q{1-1-2A},
    q{PL:} . q{ILLUMINA} . $DOUBLE_QUOTE,
);

my %base_argument = (
    stdoutfile_path => {
        input           => q{test_outfile.bam},
        expected_output => q{1> test_outfile.bam},
    },
    stderrfile_path => {
        input           => q{stderrfile.test},
        expected_output => q{2> stderrfile.test},
    },
    stderrfile_path_append => {
        input           => q{stderrfile.test},
        expected_output => q{2>> stderrfile.test},
    },
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
        input           => q{test_infile.fastq},
        expected_output => q{test_infile.fastq},
    },
    idxbase => {
        input           => q{GRCh37_homo_sapiens_-d5-.fasta},
        expected_output => q{GRCh37_homo_sapiens_-d5-.fasta},
    },
);

my %specific_argument = (
    thread_number => {
        input           => 2,
        expected_output => q{-t 2},
    },
    infile_path => {
        input           => q{test_infile_1.fastq},
        expected_output => q{test_infile_1.fastq},
    },
    interleaved_fastq_file => {
        input           => 1,
        expected_output => q{-p},
    },
    mark_split_as_secondary => {
        input           => 1,
        expected_output => q{-M},
    },
    read_group_header => {
        input           => ( join $SPACE,                  @read_group_headers ),
        expected_output => ( q{-R} . $SPACE . join $SPACE, @read_group_headers ),
    },
    second_infile_path => {
        input           => q{test_infile_2.fastq},
        expected_output => q{test_infile_2.fastq},
    },
    soft_clip_sup_align => {
        input           => 1,
        expected_output => q{-Y},
    },
    stdoutfile_path => {
        input           => q{test_outfile.bam},
        expected_output => q{1> test_outfile.bam},
    },
    stderrfile_path => {
        input           => q{stderrfile.test},
        expected_output => q{2> stderrfile.test},
    },
    stderrfile_path_append => {
        input           => q{stderrfile.test},
        expected_output => q{2>> stderrfile.test},
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&bwa_mem;

## Test both base and function specific arguments
my @arguments = ( \%required_argument, \%specific_argument );

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
