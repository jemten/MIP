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
our $VERSION = 1.02;

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
    my %perl_module = ( q{MIP::Test::Fixtures} => [qw{ test_standard_cli }], );

    test_import( { perl_module_href => \%perl_module, } );
}

use MIP::Program::Alignment::Gatk qw{ gatk_haplotypecaller };
use MIP::Test::Commands qw{ test_function };

diag(   q{Test gatk_haplotypecaller from Alignment::Gatk.pm v}
      . $MIP::Program::Alignment::Gatk::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Constants
Readonly my $SAMPLE_PLOIDY                                 => 3;
Readonly my $STANDARD_MIN_CONFIDENCE_THRESHOLD_FOR_CALLING => 10;

## Base arguments
my @function_base_commands = qw{ gatk HaplotypeCaller };

my %base_argument = (
    stderrfile_path => {
        input           => q{stderrfile.test},
        expected_output => q{2> stderrfile.test},
    },
    FILEHANDLE => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
);

## Can be duplicated with %base_argument and/or %specific_argument
## to enable testing of each individual argument
my %required_argument = (
    infile_path => {
        input           => catfile(qw{ dir infile.bam }),
        expected_output => q{--input } . catfile(qw{ dir infile.bam }),
    },
    outfile_path => {
        input           => catfile(qw{ dir outfile.bam }),
        expected_output => q{--ouputt } . catfile(qw{ dir outfile.bam }),
    },
    referencefile_path => {
        input           => catfile(qw{reference_dir human_genome_build.fasta }),
        expected_output => q{--reference }
          . catfile(qw{reference_dir human_genome_build.fasta }),
    },
);

my %specific_argument = (
    annotations_ref => {
        inputs_ref => [qw{ BaseQualityRankSumTest ChromosomeCounts }],
        expected_output =>
          q{--annotation BaseQualityRankSumTest --annotation ChromosomeCounts},
    },
    dbsnp_path => {
        input           => catfile(qw{ dir GRCh37_dbsnp_-138-.vcf }),
        expected_output => q{--dbsnp } . catfile(qw{ dir GRCh37_dbsnp_-138-.vcf }),
    },
    dont_use_soft_clipped_bases => {
        input           => 1,
        expected_output => q{--dont-use-soft-clipped-bases},
    },
    emit_ref_confidence => {
        input           => q{GVCF},
        expected_output => q{--emit-ref-confidence GVCF},
    },
    infile_path => {
        input           => catfile(qw{ dir infile.bam }),
        expected_output => q{--input } . catfile(qw{ dir infile.bam }),
    },
    outfile_path => {
        input           => catfile(qw{ dir outfile.bam }),
        expected_output => q{--output } . catfile(qw{ dir outfile.bam }),
    },
    pcr_indel_model => {
        input           => q{NONE},
        expected_output => q{--pcr-indel-model NONE},
    },
    sample_ploidy => {
        input           => $SAMPLE_PLOIDY,
        expected_output => q{--sample-ploidy } . $SAMPLE_PLOIDY,
    },
    standard_min_confidence_threshold_for_calling => {
        input           => $STANDARD_MIN_CONFIDENCE_THRESHOLD_FOR_CALLING,
        expected_output => q{--standard-min-confidence-threshold-for-calling }
          . $STANDARD_MIN_CONFIDENCE_THRESHOLD_FOR_CALLING,
    },
    use_new_qual_calculator => {
        input           => 1,
        expected_output => q{--use-new-qual-calculator},
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&gatk_haplotypecaller;

## Test both base and function specific arguments
my @arguments = ( \%base_argument, \%specific_argument );

ARGUMENT_HASH_REF:
foreach my $argument_href (@arguments) {
    my @commands = test_function(
        {
            base_commands_index        => 1,
            argument_href              => $argument_href,
            required_argument_href     => \%required_argument,
            module_function_cref       => $module_function_cref,
            function_base_commands_ref => \@function_base_commands,
            do_test_base_command       => 1,
        }
    );
}
done_testing();
