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
use autodie qw { :all };
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
Readonly my $COLON => q{:};
Readonly my $COMMA => q{,};
Readonly my $SPACE => q{ };

BEGIN {

    use MIP::Test::Fixtures qw{ test_import };

### Check all internal dependency modules and imports
## Modules with import
    my %perl_module = (
        q{MIP::Program::Variantcalling::Gatk} => [qw{ gatk_concatenate_variants }],
        q{MIP::Test::Fixtures}                => [qw{ test_standard_cli }],
    );

    test_import( { perl_module_href => \%perl_module, } );
}

use MIP::Program::Variantcalling::Gatk qw{ gatk_concatenate_variants };

diag(   q{Test gatk_concatenate_variants from Gatk.pm v}
      . $MIP::Program::Variantcalling::Gatk::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

# Create anonymous filehandle
my $FILEHANDLE = IO::Handle->new();

# For storing info to write
my $file_content;

## Store file content in memory by using referenced variable
open $FILEHANDLE, q{>}, \$file_content
  or croak q{Cannot write to} . $SPACE . $file_content . $COLON . $SPACE . $OS_ERROR;

## Given files and input
my %active_parameter = (
    java_use_large_pages => 1,
    gatk_logging_level   => q{INFO},
    temp_directory       => catdir(qw{ a test dir}),
);
my @contigs        = qw{ 1 2 3 };
my $infile_prefix  = q{infile};
my $outfile_suffix = q{.vcf};

gatk_concatenate_variants(
    {
        active_parameter_href => \%active_parameter,
        continue              => 1,
        FILEHANDLE            => $FILEHANDLE,
        elements_ref          => \@contigs,
        infile_prefix         => $infile_prefix,
        outfile_suffix        => $outfile_suffix,
    }
);

## Close the filehandle
close $FILEHANDLE;

## Then write concatenate instructions
my ($returned_command) = $file_content =~ /(GatherVcfsCloud)/xms;
ok( $returned_command, q{Wrote concatenate instructions} );

## Then also write ampersand
my ($wrote_ampersand) = $file_content =~ /(&)/xms;
ok( $wrote_ampersand, q{Wrote continue instructions} );

done_testing();
