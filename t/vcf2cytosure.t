#!/usr/bin/env perl

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
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
use MIP::Test::Commands qw{ test_function };
use MIP::Test::Fixtures qw{ test_standard_cli };

my $VERBOSE = 1;
our $VERSION = 1.03;

$VERBOSE = test_standard_cli(
    {
        verbose => $VERBOSE,
        version => $VERSION,
    }
);

## Constants
Readonly my $COMMA         => q{,};
Readonly my $MAX_FREQUENCY => 0.01;
Readonly my $SPACE         => q{ };
Readonly my $VARIANT_SIZE  => 5000;

BEGIN {

    use MIP::Test::Fixtures qw{ test_import };

### Check all internal dependency modules and imports
## Modules with import
    my %perl_module = (
        q{MIP::Program::Variantcalling::Vcf2cytosure} => [qw{ vcf2cytosure_convert }],
        q{MIP::Test::Fixtures}                        => [qw{ test_standard_cli }],
    );

    test_import( { perl_module_href => \%perl_module, } );
}

use MIP::Program::Variantcalling::Vcf2cytosure qw{ vcf2cytosure_convert };
use MIP::Test::Commands qw{ test_function };

diag(   q{Test vcf2cytosure_convert from Vcf2cytosure.pm v}
      . $MIP::Program::Variantcalling::Vcf2cytosure::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Base arguments
my @function_base_commands = qw{ vcf2cytosure };

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
    coverage_file => {
        input           => catfile(qw{ path_to_tiddit_outfiles prefix.cov }),
        expected_output => q{--coverage}
          . $SPACE
          . catfile(qw{ path_to_tiddit_outfiles prefix.tab }),
    },
    vcf_infile_path => {
        input           => q{path_to_sample_SVs.vcf},
        expected_output => q{path_to_sample_SVs.vcf},
    },
);

my %specific_argument = (
    frequency => {
        input           => $MAX_FREQUENCY,
        expected_output => q{--frequency} . $SPACE . $MAX_FREQUENCY,
    },
    frequency_tag => {
        input           => q{FRQ},
        expected_output => q{--frequency_tag FRQ},
    },
    no_filter => {
        input           => 1,
        expected_output => q{--no-filter},
    },
    outfile_path => {
        input           => q{path_to_vcf2cytosure_cgh_files},
        expected_output => q{--out path_to_vcf2cytosure_cgh_files},
    },
    sex => {
        input           => q{male},
        expected_output => q{--sex male},
    },
    variant_size => {
        input           => $VARIANT_SIZE,
        expected_output => q{--size} . $SPACE . $VARIANT_SIZE,
    },
    version => {
        input           => 1,
        expected_output => q{--version},
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&vcf2cytosure_convert;

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

######################
####SubRoutines#######
######################

sub build_usage {

## Function  : Build the USAGE instructions
## Returns   :
## Arguments : $program_name => Name of the script

    my ($arg_href) = @_;

    ## Default(s)
    my $program_name;

    my $tmpl = {
        program_name => {
            default     => basename($PROGRAM_NAME),
            store       => \$program_name,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    return <<"END_USAGE";
 $program_name [options]
    -vb/--verbose Verbose
    -h/--help Display this help message
    -v/--version Display version
END_USAGE
}
